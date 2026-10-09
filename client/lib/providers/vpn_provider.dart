import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart'; // PlatformException + rootBundle
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../brand.dart';
import '../vpn/vpn_engine.dart';
import '../vpn/proxy_core_engine.dart';
import '../vpn/singbox_config.dart';
import '../utils/rule_set_assets.dart';
import '../utils/dns_region.dart';
import '../models/server_config.dart';
import '../models/free_node.dart';
import '../models/singbox_premium.dart';
import '../services/api_service.dart';
import '../services/app_proxy_store.dart';
import '../services/free_node_service.dart';
import '../env.dart';

export '../vpn/vpn_engine.dart' show VpnStage;

enum VpnStatus    { disconnected, connecting, connected, disconnecting, error }
/// 连接通道：
/// - [direct]     UDP 直连      → 对外显示「快速模式」
/// - [relay]      wstunnel 443  → 对外显示「强力模式」
/// - [cloudflare] Cloudflare    → 对外显示「暴力模式」
enum VpnProtocol  { direct, relay, cloudflare }

/// 用户可选的「连接模式」偏好（与自动降级解耦）：
/// - [auto]       自动（默认）：直连，失败逐层降级到强力/超级
/// - [direct]     快速：仅直连 UDP，不降级
/// - [relay]      强力：直接走 wstunnel 443 中继
/// - [cloudflare] 超级：直接走 Cloudflare 中继
enum ConnMode { auto, direct, relay, cloudflare }
/// 路由模式
/// - [global]：全局模式，所有流量走 VPN（0.0.0.0/0）
/// - [smart] ：智能模式，中国大陆 IP 直连，境外流量走 VPN
enum RoutingMode  { global, smart }

/// 当前隧道来源：优质(后端下发 singbox)或免费(订阅节点)。合并后两者共用同一状态机。
enum ConnSource { premium, free }

class VpnProvider extends ChangeNotifier {
  // VPN 引擎(引擎无关抽象)。优质节点双栈期：节点已开通 sing-box（configs 下发 singbox 块）就用 sing-box，
  // 否则沿用 AmneziaWG。两个引擎常驻，但同一时刻只有一个持有系统隧道
  // （iOS/安卓单隧道限制），切换时必须先停旧的 —— 见 _useEngine。
  // 纯 sing-box 引擎（优质 + 免费统一一套）。
  final VpnEngine _sbEngine  = ProxyCoreEngine();
  late VpnEngine _engine = _sbEngine;

  /// 按节点切换引擎。两个引擎的 stage 流不同，切换时必须重订阅，否则界面会停在
  /// 旧引擎的状态上不动。切换前先停旧引擎（系统同时只允许一条隧道）。
  Future<void> _useEngine(VpnEngine next) async {
    if (identical(_engine, next)) return;
    try { await _engine.stop(); } catch (_) {}
    _engine = next;
    await _engine.initialize();
    await _stageSub?.cancel();
    _stageSub = _engine.stageStream.listen(_onStage);
  }

  /// 连接前需要停掉的另一条隧道（共享节点 sing-box）。由 app 层注入，实现系统级互斥。
  Future<void> Function()? onBeforeConnect;

  VpnStatus     _status        = VpnStatus.disconnected;
  ServerConfig? _activeServer;
  /// 当前隧道来源(合并后统一状态机)：免费连接经 runSharedTunnel 置为 free。
  ConnSource    _source        = ConnSource.premium;
  ConnSource get source => _source;
  /// 免费节点当前连的是哪个(供 UI 展示)；优质连接时清空。
  FreeNode?     activeFreeNode;
  /// 用户上次选择的是「智能分配」(true) 还是某台具体节点(false)。持久化。
  bool          _autoSelect    = true;
  bool   get autoSelect => _autoSelect;
  int?          _elapsedSecs;
  String?       _error;
  Timer?        _timer;
  Timer?        _fallbackTimer;
  Stopwatch?    _connectSw;   // 连接耗时诊断(从点连接到引擎 start 返回)
  int?          lastEngineStartMs;   // 点连接→原生引擎 start 返回(Dart 侧耗时)
  int?          lastConnectedMs;     // 点连接→真正显示已连接(含原生 libbox 起隧道)
  int?          lastPreConnectMs;    // 点击节点→connect() 进入(导航/预处理耗时)
  int?          lastUsableMs;        // 点连接→首次探测真正能上网
  int?          lastEnsurePeerMs;    // ensurePeer(往返 Vercel 再调节点 vpn-api 下发设备凭证)耗时
  String?       lastNativeDiag;      // 原生起隧道分步计时(setup/check/cmd/reload)
  DateTime?     _tapAt;              // 用户点击连接的时刻(UI 层标记)
  /// UI 在点击连接的最开始调用，用于测「点击→connect() 进入」这段(导航等)的耗时。
  void markTap() { _tapAt = DateTime.now(); }
  StreamSubscription<VpnStage>? _stageSub;

  VpnProtocol        _protocol         = VpnProtocol.direct;
  ConnMode           _connMode         = ConnMode.auto;   // 用户「连接模式」偏好
  bool               _switchingToRelay = false;

  /// 已成功下发过本机凭证的节点 id(持久化)。连这些节点时 ensurePeer 改【后台刷新、不阻塞】起隧道，
  /// 避免每次都白等 Vercel→节点往返(个别节点该往返达 ~8-10s)。节点凭证写在其 config 里是持久的。
  /// 首次连某节点仍阻塞等下发成功(否则节点不认 UUID → 连上却不通)。重装 App 会清空(data 清掉)。
  final Set<String>  _provisionedServerIds = {};
  Future<void> _persistProvisioned() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('provisioned_servers', _provisionedServerIds.toList());
    } catch (_) {}
  }
  /// 列表页预热(对所有节点 ensurePeer)成功后调用，把这些节点标记为已下发 → 后续首连也不阻塞。
  void markServersProvisioned(Iterable<String> ids) {
    final before = _provisionedServerIds.length;
    _provisionedServerIds.addAll(ids);
    if (_provisionedServerIds.length != before) _persistProvisioned();
  }
  // 用户主动断开标志：置位后，任何挂起的连通性探测/回退计时器都不得再发起
  // 新的连接尝试（修复「手动断开后又自动切到下一模式」）。connect() 清零。
  bool               _userInitiatedDisconnect = false;

  /// 智能分流诊断（AWG 时代用于「我的→错误信息」）。sing-box 的智能分流在
  /// SingboxConfig 内完成，这里暂不产出，保留字段供 UI 读取（恒为 null）。
  String? smartRoutingReport;

  RoutingMode        _routingMode      = RoutingMode.global;

  // 会话级钉死端口：UDP 直连时在 connect() 时基于时间计算一次并保存。
  // 一旦连接建立，整个会话期间复用此端口，绝不重算——即使将来加入断线
  // 自动重连，也必须沿用此值，避免跨小时窗口时端口漂移。disconnect() 清空。
  int?               _sessionPort;

  // ── 本地用量计量（#8）──────────────────────────────────────────
  // 用量在【本地】累计（隧道适配器 rx+tx），上限从服务器拉取（setDailyQuota）。
  // 按 UTC 日期重置，与服务端每日额度对齐。
  int                _dailyUsed   = 0;       // 今日已用字节（本地累计）
  // 实时速率（字节/秒），由 rx/tx 增量计算，用于主页"上传/下载"展示
  int                _downBps     = 0;
  int                _upBps       = 0;
  int                _lastRx      = -1;
  int                _lastTx      = -1;
  int                _lastSpeedMs = 0;
  String             _usageDay    = '';      // 当前计量所属 UTC 日期 yyyy-mm-dd
  int?               _statsBaseline;         // 上次轮询的隧道累计值，用于求增量
  int?               _quotaBytes;            // 服务器下发的今日上限（仅用于流量展示）
  Timer?             _usageTimer;

  // 连接后的实时延迟（展示用）：连上后每 30s 探测一次外网 RTT，经算法优化后展示，
  // 不再沿用连接前冻结的节点延迟。断开清空。
  int?               _connectedPingMs;
  Timer?             _pingTimer;

  // ── 基于时间的免费试用（#3 + 看广告延长 #4）──────────────────────
  // 免费用户首次连接成功当天记 _trialStartMs，倒计时按【墙钟】连续走，
  // 断开也不停；到期当天禁连，次日(UTC)重置。上限 _timeLimitSec 从服务器拉取，
  // 看激励广告每次 +kAdRewardMinutes 分钟累加到 _adBonusSec。
  int?               _timeLimitSec;          // 服务器下发的每日试用秒数（null=无限/付费）
  int?               _trialStartMs;          // 今日首次连接成功的时间戳(ms)
  int                _adBonusSec = 0;        // 今日通过看广告累加的额外秒数
  String             _trialDay   = '';       // 计量所属 UTC 日期
  bool               _trialExceeded = false; // 今日试用是否已用尽
  bool               _trialLoaded   = false; // 试用状态是否已从磁盘加载（防竞态清零）
  Timer?             _trialTimer;

  VpnStatus     get status       => _status;
  ServerConfig? get activeServer => _activeServer;
  int?          get elapsedSecs  => _elapsedSecs;
  String?       get error        => _error;
  VpnProtocol   get protocol     => _protocol;
  ConnMode      get connMode     => _connMode;
  bool          get isRelayMode  => _protocol != VpnProtocol.direct;
  RoutingMode   get routingMode  => _routingMode;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy      => _status == VpnStatus.connecting ||
                          _status == VpnStatus.disconnecting;
  bool get isDisconnecting => _status == VpnStatus.disconnecting;

  // ── 本地用量/试用对外接口 ────────────────────────────────────
  int   get dailyUsed     => _dailyUsed;
  // 实时上/下行速率（格式化字符串，如 "1.2 MB/s"），未连接时为 "0 B/s"
  String get downloadSpeedStr => _fmtBps(_downBps);
  String get uploadSpeedStr   => _fmtBps(_upBps);
  String _fmtBps(int b) {
    if (b <= 0) return '0 B/s';
    const u = ['B', 'KB', 'MB', 'GB'];
    double v = b.toDouble(); int i = 0;
    while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
    return '${v.toStringAsFixed(v < 10 && i > 0 ? 1 : 0)} ${u[i]}/s';
  }
  int?  get quotaBytes    => _quotaBytes;
  /// 连接后展示用的优化延迟（ms）；未连接或首次探测前为 null。
  int?  get connectedPingMs => _connectedPingMs;

  /// 当前是否处于「按时间免费试用」模式（免费用户）。
  bool get isFreeTrial    => _timeLimitSec != null;
  /// 今日总可用秒数 = 基础上限 + 看广告奖励。
  int  get trialTotalSec  => (_timeLimitSec ?? 0) + _adBonusSec;
  /// 今日剩余秒数（已开始则按墙钟扣减；未开始则等于总额度）。
  int  get trialRemainingSec {
    if (_timeLimitSec == null) return 0;
    if (_trialStartMs == null) return trialTotalSec;
    final elapsed = (DateTime.now().millisecondsSinceEpoch - _trialStartMs!) ~/ 1000;
    final r = trialTotalSec - elapsed;
    return r > 0 ? r : 0;
  }
  /// 试用是否已用尽（免费用户额度耗尽 → 禁连，可看广告或次日恢复）。
  /// 实时按墙钟计算：不依赖只在连接时运行的 1s 定时器，断开状态下时长归零也能正确判定。
  bool get quotaExceeded =>
      _trialExceeded ||
      (_timeLimitSec != null && _trialStartMs != null && trialRemainingSec <= 0);

  static String _utcDay() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  // 任何挂起的异步流程（探测/回退）遇到以下情况都应中止
  bool get _aborted =>
      _userInitiatedDisconnect ||
      _status == VpnStatus.disconnecting ||
      _status == VpnStatus.disconnected;

  // 显示语言：尊重用户在设置里的语言覆盖(LocaleController)，而非只看设备 locale，
  // 否则中文设备切英文后 statusLine/modeLabel/错误文案仍是中文。
  static bool _isZh() => Brand.isZh;

  /// 当前模式的对外名称（按系统语言本地化）。
  String get modeLabel {
    final zh = _isZh();
    switch (_protocol) {
      case VpnProtocol.direct:     return zh ? '快速模式' : 'Fast Mode';
      case VpnProtocol.relay:      return zh ? '强力模式' : 'Strong Mode';
      case VpnProtocol.cloudflare: return zh ? '暴力模式' : 'Ultra Mode';
    }
  }

  /// 主界面状态文案（连接中 / 已连接 + 模式 / 断开中 / 出错 / 未连接）。
  /// 只有在真正验证流量畅通后状态才会变为 connected，连接过程一律显示「连接中」。
  String get statusLine {
    final zh = _isZh();
    switch (_status) {
      case VpnStatus.connected:
        return zh ? '$modeLabel · 已连接' : '$modeLabel · Connected';
      case VpnStatus.connecting:
        return zh ? '$modeLabel 连接中…' : 'Connecting ($modeLabel)…';
      case VpnStatus.disconnecting:
        return zh ? '正在断开…' : 'Disconnecting…';
      case VpnStatus.error:
        return zh ? '连接出错' : 'Connection error';
      case VpnStatus.disconnected:
        return zh ? '未连接' : 'Not connected';
    }
  }

  // ── 初始化（app 启动时调用一次）────────────────────────────
  // 网络适配器的对外描述已移入 AmneziaWgEngine（属引擎实现细节）。
  Future<void> initialize() async {
    // 先加载试用状态（必须在任何 setTimeQuota/_rollTrialDayIfNeeded 之前完成，
    // 否则启动竞态会把奖励时长清零）。AmneziaWG.initialize() 是慢的原生调用，放后面。
    await _loadTrial();
    await _loadUsage();
    await _engine.initialize();
    _stageSub = _engine.stageStream.listen(_onStage);

    // 恢复上次选择的路由模式；首次无记录时：中文用户默认「智能」，其它默认「全局」。
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('routing_mode');
    if (saved == RoutingMode.global.name) {
      _routingMode = RoutingMode.global;
    } else if (saved == RoutingMode.smart.name) {
      _routingMode = RoutingMode.smart;
    } else {
      // 首次安装、无记录：中文用户默认「智能」（境内直连/境外走 VPN + 分应用白名单）；
      // 非中文用户默认「全局」（所有流量进隧道，海外用户预期）。智能/全局切换现已
      // 国内外都显示，用户可自行切换；但分应用白名单仍仅中文壳生效（见 _applyAppProxy
      // 的 isZh 门控），故非中文即使切到智能也是全隧道、不会只放 26 个 App。
      _routingMode = _isZh() ? RoutingMode.smart : RoutingMode.global;
    }
    notifyListeners();
    // 恢复已下发凭证的节点缓存(连接时据此决定 ensurePeer 要不要阻塞起隧道)。
    _provisionedServerIds.addAll(prefs.getStringList('provisioned_servers') ?? const []);
    // 恢复「智能分配 / 手动选择」偏好（默认智能）
    _autoSelect = prefs.getBool('auto_select') ?? true;
    // 恢复「连接模式」偏好（默认自动）
    final cmName = prefs.getString('conn_mode');
    _connMode = ConnMode.values.firstWhere((e) => e.name == cmName,
        orElse: () => ConnMode.auto);

    // 冷启动采纳已在运行的隧道（返回键退后台后进程被系统回收又重开的情况）：
    // 直接显示「已连接」，避免用户再点连接而叠加第二条隧道；试用沿用已持久化
    // 的开始时间继续倒计时（不会重置回 30 分钟）。
    await _adoptRunningTunnel();

    // 常驻倒计时：一旦试用开始(_trialStartMs 有值)，无论是否连接都按墙钟持续走，
    // UI 每秒刷新、归零即触发禁连。修复「切到别的页/连共享节点后时长显示不动、
    // 归零却仍能连优质」。
    _ensureTrialTicker();
  }

  /// 确保倒计时定时器在运行（幂等）。付费用户 _recomputeTrial 内部会自动 no-op。
  void _ensureTrialTicker() {
    _trialTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _recomputeTrial());
  }

  Future<void> _adoptRunningTunnel() async {
    try {
      final st = await _engine.stage();
      if (st == VpnStage.connected && _status != VpnStatus.connected) {
        _status        = VpnStatus.connected;
        _statsBaseline = null;
        _startUsagePolling();
        _startTrialTracking();   // 复用已持久化 _trialStartMs，墙钟继续
        _startConnectedPing();   // 冷启动采纳已连隧道，同样开始刷新延迟
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 仅在「冷启动采纳了正在运行的隧道」时，把 activeServer 绑回上次的【真实】节点。
  /// 关键：绝不绑定 display-only 的公开节点（否则主页连接按钮会一直把它当展示节点
  /// 而跳登录、点不动）；未连接时不绑（让主页用 displayServers.first 即可）。
  Future<void> bindActiveServer(List<ServerConfig> servers) async {
    if (!isConnected) return;
    if (_activeServer != null && !_activeServer!.isDisplayOnly) return;
    final real = servers.where((s) => !s.isDisplayOnly).toList();
    if (real.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('last_server_id');
    _activeServer = real.firstWhere((s) => s.id == id, orElse: () => real.first);
    notifyListeners();
  }

  // ── 切换路由模式 ─────────────────────────────────────────
  Future<void> setRoutingMode(RoutingMode mode) async {
    if (_routingMode == mode) return;
    _routingMode       = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('routing_mode', mode.name);
    // 注：不再联动分应用设置。优质节点只按 GeoIP-CN(智能)/全局分流，不做按应用；
    // 按应用分流归免费节点(见 AppProxyStore + SharedNodeProvider.connect)。
  }

  void _onStage(VpnStage stage) {
    // 归属守卫：仅当隧道明确归「免费」时忽略这些 stage 事件(免费连接时优质不要误判自己
    // 也连上/断开)。null/premium 时维持原行为,不影响冷启动接管等逻辑。
    if (ProxyCoreEngine.activeOwner == 'free') return;
    switch (stage) {
      case VpnStage.connected:
        // 隧道接口已 UP，但流量未必通。一律先保持「连接中」，等连通性验证
        // 通过后再由 _postConnectCheck / _postRelayCheck 置为 connected（#5）。
        if (_userInitiatedDisconnect) break;  // 用户已断开，忽略迟到的 connected
        // sing-box 引擎上报 connected → 直接置已连接（sing-box 自己做连通性保障）。
        _fallbackTimer?.cancel();
        if (_connectSw != null && lastConnectedMs == null) {
          lastConnectedMs = _connectSw!.elapsedMilliseconds;
        }
        lastNativeDiag = ProxyCoreEngine.lastConnectedDiag;
        _status = VpnStatus.connected;
        _startDiagPolling();
        _startUsagePolling();   // 速率轮询(优质)——幂等,确保速度能显示
        _startTrialTracking();  // 连上即开始免费时长倒计时(付费用户内部 no-op)
      case VpnStage.connecting:
        _status = VpnStatus.connecting;
      case VpnStage.disconnected:
        _status = VpnStatus.disconnected;
        _appliedTunScope = null;   // 隧道已断，下次启动按首启处理(无需比对旧分应用范围)
        // 隧道断开 → 作废出口地区判定：连接期间(App 自身也进隧道)量到的是节点所在国，
        // 不重置会让免费源选择/自动 DNS 分流继续按"上次连的海外节点"工作(总拉海外源)。
        FreeNodeService.instance.resetEgressCache();
        _stopDiagPolling();
        _stopTimer();
        _usageTimer?.cancel();   // 隧道已断，停止用量轮询（不再有适配器可读）
        _stopConnectedPing();
        // 中继切换过程中不清除 activeServer；
        // _switchingToRelay 在此处故意不重置——需等到
        // relay 的 startVpn 触发 connected 后才置 false，
        // 以便 connected 分支能正确识别并取消 _fallbackTimer。
        if (!_switchingToRelay && _activeServer != null && _error == null) {
          _activeServer = null;
        }
      case VpnStage.disconnecting:
        _status = VpnStatus.disconnecting;
      default:
        break;
    }
    notifyListeners();
  }

  // ── 连接（三层防护机制）───────────────────────────────────────────────────────
  //
  //  层 1：AmneziaWG 直连 + 端口跳变（AWG 包混淆，GFW 难以识别）
  //  层 2：wstunnel WebSocket over HTTPS 443（流量伪装为 HTTPS）
  //  层 3：Cloudflare Tunnel（服务器 IP 完全隐藏，GFW 无从封锁）
  //
  Future<void> connect(ServerConfig server) async {
    // 连接耗时计时：放在最顶端，连 onBeforeConnect(停免费引擎)/预停旧隧道一起计入。
    _connectSw = Stopwatch()..start();
    lastEngineStartMs = null;
    lastConnectedMs = null;
    lastUsableMs = null;
    lastPreConnectMs = _tapAt != null ? DateTime.now().difference(_tapAt!).inMilliseconds : null;
    _tapAt = null;
    // 免费时长已用尽：禁止任何新连接（不管从主页还是节点列表点的）。#1
    if (quotaExceeded) {
      _trialExceeded = true;   // 同步缓存标志
      _error  = _isZh()
          ? '免费时长已用完，看广告或升级后再连接'
          : 'Free time used up. Watch an ad or upgrade to connect.';
      _status = VpnStatus.disconnected;
      notifyListeners();
      return;
    }
    // #1 网络预检(快而糙)：WiFi/移动数据都没有时直接提示,不进连接流程(否则 sing-box 仍会
    // 把 tun 建起来、UI 误显示已连接)。
    if (!await VpnProvider.hasActiveNetwork()) {
      _error  = _isZh() ? '无网络连接，请检查 WiFi 或移动数据'
                        : 'No network. Check WiFi or mobile data.';
      _status = VpnStatus.disconnected;
      notifyListeners();
      return;
    }
    // 兜底：进入连接前先断开系统上所有本 App VPN——
    // ① 停掉另一条引擎(共享 sing-box)，系统级只允许一条隧道；
    // ② 若本引擎(WireGuard)上一次还有残留隧道，先停掉再起新的，防止残留连接与
    //    其它客户端相互干扰。Android 上建立新隧道也会自动顶替其它 App 的现有 VPN。
    try { await onBeforeConnect?.call(); } catch (_) {}
    // 不先 stop 当前隧道：原生会在已有实例时【热重载】新配置,避免 stop/start 时序竞争
    // (旧 stopBox 线程在新 start 后才跑会把新 tun 关掉)。首连时无实例 → 原生全量启动。
    _error            = null;
    _status           = VpnStatus.connecting;
    _source           = ConnSource.premium;   // 优质连接：本条隧道归优质
    activeFreeNode    = null;
    _activeServer     = server;
    _userInitiatedDisconnect = false;  // 新的连接尝试，解除断开锁
    _fallbackTimer?.cancel();
    _statsBaseline    = null;   // 新隧道，用量基线重置（首个轮询重新建立基线）
    notifyListeners();

    try {
      // 0. 按需建 peer：确保该节点服务器上已添加本设备（on-demand provisioning）。
      //    【必须 await】首连/重装后设备是新的 sb_uuid，若不等它下发到节点就起隧道，
      //    节点不认识该 UUID → 隧道起来但 unknown UUID → "显示已连接却上不了网"。
      //    只花 1-2 秒(往返 Vercel 再调节点 vpn-api);真正的 6 秒卡顿是 teardown 空等,已单独修。
      //    幂等：已下发过则很快返回。失败也继续(best-effort),结果记入 _lastEnsurePeerOk 供诊断。
      if (!server.isDisplayOnly) {
        if (_provisionedServerIds.contains(server.id)) {
          // 已对该节点下发过 → 后台幂等刷新,不阻塞起隧道(省去 Vercel→节点往返的几~十秒)。
          lastEnsurePeerMs = 0;
          ApiService.instance.ensurePeer(serverIds: [server.id])
              .then((ok) { if (ok) _lastEnsurePeerOk = true; }).catchError((_) => false);
        } else {
          // 首次连该节点:必须等凭证下发成功再起隧道,否则节点不认 UUID → 连上却不通。
          final esw = Stopwatch()..start();
          try {
            _lastEnsurePeerOk = await ApiService.instance.ensurePeer(serverIds: [server.id]);
          } catch (_) { _lastEnsurePeerOk = false; }
          lastEnsurePeerMs = esw.elapsedMilliseconds;
          if (_lastEnsurePeerOk == true) { _provisionedServerIds.add(server.id); _persistProvisioned(); }
        }
      }

      // 纯 sing-box 客户端：优质节点必须已开通 sing-box（后端下发 singbox 块）。
      // 老的 AWG-only 节点不再支持 —— 服务端仍为老客户端保留 AWG，但本客户端只走 sing-box。
      // 连接模式（快速/强力/超级）映射到 hy2/reality/ws 由 _pickSingboxOutbound 决定。
      final sb = server.singbox;
      if (sb == null || !sb.usable) {
        _error  = _isZh() ? '该节点暂不可用，请选择其它节点'
                          : 'This node is unavailable, please pick another.';
        _status = VpnStatus.error;
        notifyListeners();
        return;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_server_id', server.id);
      } catch (_) {}
      await _connectViaSingbox(server, sb);
    } on PlatformException catch (e) {
      if (e.code == 'Permissions are not given' ||
          (e.message ?? '').contains('Permissions are not given')) {
        // 用户未授权：隧道没真正建立，无需拆除。
        _error  = '请在刚才弹出的对话框中允许 VPN，然后重新点击连接';
        _status = VpnStatus.disconnected;
      } else {
        // 启动失败：可能已部分建立适配器/路由，强制拆除避免残留路由黑洞。
        try { await _engine.stop(); } catch (_) {}
        _error  = e.message ?? e.toString();
        _status = VpnStatus.error;
      }
      notifyListeners();
    } catch (e) {
      try { await _engine.stop(); } catch (_) {}
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  // ── 优质节点走 sing-box（迁移期）────────────────────────────────────────
  /// 用 sing-box 连优质节点。协议层由后端下发的 singbox 块决定：
  /// 快速=Hysteria2 / 强力=VLESS+Reality / 超级=VLESS+WS（阶段 2）。
  ///
  /// 路由、DNS、广告域名强制代理这些**完全复用免费节点那一套**（SingboxConfig），
  /// 这正是迁移的主要收益：按域名分流取代按 IP 分流，三端一套逻辑。
  ///
  /// 端口跳跃不在这里算 —— 范围由后端放在 hysteria2.ports 里，交给 sing-box 原生
  /// 完成（见 docs/singbox-migration.md §9）。
  Future<void> _connectViaSingbox(ServerConfig server, SingboxPremium sb) async {
    final outbound = _pickSingboxOutbound(sb);
    if (outbound == null) {
      _error = '该节点暂不支持当前连接模式';
      _status = VpnStatus.disconnected;
      notifyListeners();
      return;
    }

    await _useEngine(_sbEngine);

    // 按实际选中的协议设模式标签：hy2=快速 / reality=强力 / ws=超级（供 modeLabel 显示）。
    final obType = outbound['type'];
    final isWs = (outbound['transport'] as Map?)?['type'] == 'ws';
    _protocol = obType == 'hysteria2'
        ? VpnProtocol.direct
        : (isWs ? VpnProtocol.cloudflare : VpnProtocol.relay);

    // 分应用(代理名单/直连名单)始终生效，与路由模式(智能/全局)正交——名单决定"哪些 App 进隧道"，
    // 模式/地区决定"进了隧道怎么走"。代理名单必须含本 App + Google Play 服务(承载 AdMob)，否则广告被墙。
    List<String>? inc, exc, incProc, excProc;
    {
      final pkgs = (await AppProxyStore.loadPkgs()).toList();
      if (pkgs.isNotEmpty) {
        final white = await AppProxyStore.loadMode() == 'white';
        if (Platform.isAndroid)      { if (white) inc = pkgs; else exc = pkgs; }
        else if (Platform.isWindows) { if (white) incProc = pkgs; else excProc = pkgs; }
      }
      const selfPkg = 'com.mirrorspeed.vpn';
      const gmsPkg  = 'com.google.android.gms';
      if (Platform.isAndroid) {
        if (inc != null) {
          var l = inc;
          for (final p in [selfPkg, gmsPkg]) { if (!l.contains(p)) l = [...l, p]; }
          inc = l;
        }
        if (exc != null) exc = exc.where((p) => p != selfPkg && p != gmsPkg).toList();
      }
    }

    // 智能模式：airlane-cn 规则集(域名+IP 级)优先；Apple 走扩展打包，其它平台释放到磁盘后传路径。
    // 释放失败再回退 cn_cidr(ip_cidr，仅 IP 级)。
    // DNS 地区方案：海外(auto 确知境外 / 手动海外)不加 airlane-cn 国内直连。
    final overseas = await DnsRegionStore.effectiveOverseas();
    List<String>? cnCidrs;
    String? cnRsPath;
    if (_routingMode == RoutingMode.smart && !overseas) {
      if (!(Platform.isIOS || Platform.isMacOS)) {
        cnRsPath = await RuleSetAssets.cnRuleSetPath();
      }
      cnCidrs = await _loadCnCidrs();
    }

    final cfg = SingboxConfig.build(
      outbound,
      smart: _routingMode == RoutingMode.smart,
      includePackages: inc, excludePackages: exc,
      includeProcesses: incProc, excludeProcesses: excProc,
      cnCidrs: cnCidrs, cnRuleSetPath: cnRsPath, overseas: overseas,
      ipv6: await _tunIpv6(),   // 让 tun 接管 ::/0，堵 IPv6 泄漏(否则 ip.sb 等双栈站走真实 v6 绕过隧道)
    );
    debugPrint('[VPN] 优质节点走 sing-box，协议=${outbound['type']}'
        '，inc=${inc?.length ?? 0} exc=${exc?.length ?? 0}'
        '，配置就绪耗时=${_connectSw?.elapsedMilliseconds}ms');
    ProxyCoreEngine.activeOwner = 'premium';   // 本条隧道归优质,免费 provider 据此忽略这些 stage 事件
    await _startEngine(cfg);
    lastEngineStartMs = _connectSw?.elapsedMilliseconds;
    debugPrint('[VPN] sing-box 引擎 start 返回，总耗时=${lastEngineStartMs}ms');

    if (!_userInitiatedDisconnect && _status == VpnStatus.connecting) {
      _status = VpnStatus.connected;
      _statsBaseline = null;
      _startUsagePolling();   // 优质节点也启动速率轮询(读 transferRxTx 算上下行)——否则速度恒 0
      _startTrialTracking();  // 连上即开始免费时长倒计时(付费用户内部 no-op)
      notifyListeners();
    }
    _measureUsable();   // 打点：隧道起来后多久能真正通网(不阻塞)
  }

  /// tun 是否声明 IPv6(接管 ::/0)。安卓一律声明——否则双栈站点(如 ip.sb)的 IPv6 流量会
  /// 绕过 IPv4-only 隧道直连、泄漏真实 IP；声明后 v6 要么进隧道、要么 fail-closed，绝不泄漏。
  /// Windows/Apple 需真有可用 v6 才声明：在 IPv6 被禁用的机器上给 tun 设 v6 地址会 FATAL。
  Future<bool> _tunIpv6() async {
    if (Platform.isAndroid) return true;
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv6,
          includeLinkLocal: false, includeLoopback: false);
      for (final i in ifaces) {
        if (i.addresses.any((a) => !a.isLoopback && !a.isLinkLocal)) return true;
      }
    } catch (_) {}
    return false;
  }

  // 分应用范围(include/exclude_package)的指纹。Android VpnService 的 allowed/disallowed
  // apps 在 sing-box 热重载时【无法变更】，故范围一旦变化必须整条停→起，让 VpnService 带
  // 新名单重建；否则改了分应用再(热重载)连接，新名单不生效(尤其默认空名单起隧道后再加名单)。
  String? _appliedTunScope;
  String _tunScopeOf(Map<String, dynamic> cfg) {
    final inbs = cfg['inbounds'];
    final tun = (inbs is List && inbs.isNotEmpty && inbs.first is Map)
        ? inbs.first as Map : const {};
    return jsonEncode({'i': tun['include_package'], 'e': tun['exclude_package']});
  }

  /// 统一的引擎启动入口：分应用范围变了就先整条停再起(不能热重载)，否则照常(热重载/首启)。
  Future<void> _startEngine(Map<String, dynamic> cfg) async {
    final scope = _tunScopeOf(cfg);
    if (_appliedTunScope != null && _appliedTunScope != scope) {
      try { await _engine.stop(); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _engine.start(EngineStartParams(singboxConfig: cfg));
    _appliedTunScope = scope;
  }

  /// 诊断：从点连接到首次「能真正上网」(探测 generate_204 成功)的耗时。不阻塞连接。
  Future<void> _measureUsable() async {
    final sw = _connectSw;
    if (sw == null) return;
    for (int i = 0; i < 30; i++) {           // 最多 ~15s
      if (_status != VpnStatus.connected || _userInitiatedDisconnect) return;
      if (await _probeConnectivity()) {
        lastUsableMs = sw.elapsedMilliseconds;
        notifyListeners();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  List<String>? _cnCidrsCache;
  /// 加载并缓存中国 IP 段(assets/routes/cn_cidr.txt)，供智能模式 ip_cidr 直连。
  Future<List<String>> _loadCnCidrs() async {
    if (_cnCidrsCache != null) return _cnCidrsCache!;
    try {
      final txt = await rootBundle.loadString('assets/routes/cn_cidr.txt');
      _cnCidrsCache = txt.split('\n').map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    } catch (_) {
      _cnCidrsCache = const [];
    }
    return _cnCidrsCache!;
  }

  /// 按用户选择的连接模式挑一层协议；该层未下发则按 快速→强力→超级 顺序降级，
  /// 保证"后端只开通了部分协议"时仍能连上。
  Map<String, dynamic>? _pickSingboxOutbound(SingboxPremium sb) {
    final hy2     = sb.hysteria2?.outbound(sb.hy2Password);
    final reality = sb.reality?.outbound(sb.uuid);
    final ws      = sb.ws?.outbound(sb.uuid);
    switch (_connMode) {
      case ConnMode.direct:     return hy2 ?? reality ?? ws;
      case ConnMode.relay:      return reality ?? ws ?? hy2;
      case ConnMode.cloudflare: return ws ?? reality ?? hy2;
      case ConnMode.auto:       return hy2 ?? reality ?? ws;
    }
  }

  // ── 断开 ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;  // 手动断开即断开，禁止任何自动回退（#4）
    // 【修复免费节点被误拆】本 App 只有一条原生 sing-box 服务,优质/免费两 provider 共用它。
    // 连免费时会调 onNeedStopOther=_vpn.disconnect() 停优质;若优质本就没在跑,这里绝不能再
    // 发原生 stop —— 否则 stopBox(后台线程)可能在免费 START 之后才执行,把免费刚建好的 tun
    // 关掉 → "write tun: I/O error" → 免费 egress 探测失败、判定连不上。与 _teardown 的守卫对称。
    if (_status == VpnStatus.disconnected && !_switchingToRelay) {
      _fallbackTimer?.cancel();
      notifyListeners();
      return;
    }
    // 先把会卡住的计时器停掉（不要 await 任何原生调用，否则若平台调用挂起会卡死断开）。
    _fallbackTimer?.cancel();
    _usageTimer?.cancel();
    _stopConnectedPing();
    _sessionPort      = null;    // 主动断开后，下次连接重新基于时间计算端口
    _switchingToRelay = false;   // 确保 disconnected 事件不误判为中继切换中
    _status = VpnStatus.disconnecting;
    notifyListeners();
    // 关键：第一步就拆隧道（带超时，避免平台通道挂起导致永远断不开）。
    try {
      await _engine.stop()
          .timeout(const Duration(seconds: 6), onTimeout: () {});
    } catch (e) {
      debugPrint('[VPN] stopVpn error: $e');
    }
    _status   = VpnStatus.disconnected;   // 明确置为已断开（不依赖 stage 事件）
    _source   = ConnSource.premium;
    activeFreeNode = null;
    notifyListeners();
  }

  // ── 免费节点复用同一引擎/状态机(合并) ───────────────────────────
  // SharedNodeProvider 负责"挑哪个节点/测速/自动换/egress 校验",但隧道的启停与连接状态
  // 全部经这里,保证全 App 只有一个"已连接"真相(根治优质/免费状态打架)。cfg 由免费侧构建
  // (含分应用黑白名单 + airlane-cn 规则集)。
  /// 用给定 sing-box 配置启动免费隧道：先停当前隧道(无论来源),再起;不乐观置连接——
  /// 由免费侧 egress 探测通过后调 [markSharedConnected]。
  Future<void> runSharedTunnel(Map<String, dynamic> cfg, {FreeNode? node}) async {
    _userInitiatedDisconnect = false;
    // 不先 stop 当前隧道：原生在已有实例时热重载新配置(切换免费节点无缝,无 stop/start 竞争)。
    _stopConnectedPing();
    _fallbackTimer?.cancel();
    _source        = ConnSource.free;
    _activeServer  = null;
    activeFreeNode = node;
    _error         = null;
    _status        = VpnStatus.connecting;
    notifyListeners();
    await _useEngine(_sbEngine);
    ProxyCoreEngine.activeOwner = 'free';
    await _startEngine(cfg);
  }

  /// 免费侧 egress 探测通过 → 显式置「已连接」(免费不走乐观连接,以真实出网为准)。
  void markSharedConnected() {
    if (_userInitiatedDisconnect || _source != ConnSource.free) return;
    _status = VpnStatus.connected;
    notifyListeners();
  }

  /// 免费侧读隧道累计收发字节(速率计量用)，走同一引擎。
  Future<List<int>> sharedTransferRxTx() => _engine.transferRxTx();

  /// 网络预检：有无可用网络(WiFi/移动数据/以太网)。WiFi+移动数据都关时返回 false。
  /// 用 connectivity_plus(可靠)——安卓的网卡列表即使没网也常残留 rmnet/dummy 带地址,不可信。
  /// 探测异常一律放行(返回 true),避免误伤。供连接前拦截"没网却显示已连接"。
  static Future<bool> hasActiveNetwork() async {
    try {
      final r = await Connectivity().checkConnectivity()
          .timeout(const Duration(seconds: 2));
      // connectivity_plus 6.x 返回 List;仅 none(或空)= 无网络。
      return r.any((e) => e != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  // ── 切换服务器 ───────────────────────────────────────────────
  Future<void> switchServer(ServerConfig server) async {
    // 不先 disconnect：直接 connect,原生检测到已有实例会【热重载】新配置(不拆 tun)。
    // 旧的"disconnect 再 connect"会让旧会话的 stopSelf→onDestroy 延迟广播 disconnected,
    // 在新连接之后才到 → 把状态打回断开(表现为"切换后连上又断")。
    await connect(server);
  }

  // ── 计时器 ───────────────────────────────────────────────────
  void _startTimer() {
    _elapsedSecs = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSecs = (_elapsedSecs ?? 0) + 1;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _elapsedSecs = null;
  }

  /// 通用连通性探测：经隧道请求外网 generate_204，5 秒超时。
  /// 返回 true 表示隧道内流量真正畅通。
  Future<bool> _probeConnectivity() async {
    try {
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 204 || res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  // ── 连接后实时延迟（每 30s 刷新，展示用）──────────────────────────────────
  // 隧道建立后，连接前测得的节点延迟已失去意义（且被冻结）。这里每 30s 探测一次
  // 经隧道到外网的 RTT，按体感优化后展示，让主页「延迟」数值随实时网络刷新。
  void _startConnectedPing() {
    _pingTimer?.cancel();
    _measureConnectedPing();   // 立即测一次，避免等 30s
    _pingTimer = Timer.periodic(
      const Duration(seconds: 30), (_) => _measureConnectedPing());
  }

  void _stopConnectedPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _connectedPingMs = null;
  }

  // 优化公式（与节点列表展示口径一致，原始 RTT 偏大按体感缩放；设 5ms 下限防 0）。
  int _optimizePing(int raw) {
    int v;
    if (raw < 100)       v = raw;
    else if (raw <= 200) v = (raw / 2).round();
    else                 v = (raw / 3).round();
    return v < 5 ? 5 : v;
  }

  Future<void> _measureConnectedPing() async {
    if (_status != VpnStatus.connected) return;
    try {
      final sw = Stopwatch()..start();
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      sw.stop();
      if (res.statusCode == 204 || res.statusCode < 400) {
        _connectedPingMs = _optimizePing(sw.elapsedMilliseconds);
        notifyListeners();
      }
    } catch (_) {
      // 单次失败保留上次值，不清零（避免偶发抖动把延迟显示成 --）
    }
  }

  // ── App 从后台/深度休眠恢复时调用（由 app.dart 生命周期监听触发）──────────
  //
  // 长时间 Doze 休眠后存在一个无法自愈的死锁场景：
  //   1. 休眠期间 PersistentKeepalive(25s) 定时器被系统冻结，服务端
  //      conntrack UDP 条目（默认 120s）过期；
  //   2. 同时服务端每小时端口轮换可能已刷掉本会话钉死端口的 DNAT 规则；
  //   → 唤醒后隧道仍显示 connected，但发往钉死端口的包命中 NEW 状态、
  //     无匹配规则被丢弃；WireGuard 重握手仍打向同一死端口，永远连不上。
  //
  // 这里在恢复时主动探测，若隧道已死则整体重连——disconnect() 清空
  // _sessionPort，connect() 随即按当前时间重新派生一个有效端口。
  Future<void> onAppResumed() async {
    // 先与原生隧道状态对齐：切后台再回来时 UI 可能漏掉了 stage 事件而误显示
    // 未连接（状态栏 VPN 图标其实还在）。以原生为准纠正。
    if (!_switchingToRelay) {
      try {
        final st = await _engine.stage();
        final up = st == VpnStage.connected;
        if (up && _status != VpnStatus.connected) {
          _status = VpnStatus.connected;
          notifyListeners();
        } else if (!up && _status == VpnStatus.connected) {
          _status = VpnStatus.disconnected;
          notifyListeners();
        }
      } catch (_) {}
    }

    if (_status != VpnStatus.connected || _switchingToRelay) return;
    final server = _activeServer;
    if (server == null) return;

    // 给系统网络栈一点恢复时间再探测，避免误判
    await Future.delayed(const Duration(seconds: 2));
    if (_status != VpnStatus.connected || _switchingToRelay) return;

    if (await _probeConnectivity()) {
      debugPrint('[VPN] resume 健康检查通过，保持连接');
      return;
    }

    debugPrint('[VPN] resume 健康检查失败，隧道已死，重连中…');
    await disconnect();                                  // 清空 _sessionPort
    await Future.delayed(const Duration(milliseconds: 400));
    await connect(server);                               // 重新派生端口并连接
  }

  // ── 延迟测量（请求各自服务器的 health 端点）──────────────────
  // 每台 VPN 服务器单独测量，反映从用户当前网络到该服务器的真实延迟。
  // 采用 10 秒滚动平均（见 ServerConfig.addLatencySample）：连测 [rounds] 轮，
  // 每轮间隔 [gap]，样本累入各 server 的滑动窗口，读取时取均值，>300ms 由 UI 截断显示。
  Future<void> measureLatencies(
    List<ServerConfig> servers, {
    int rounds = 3,
    Duration gap = const Duration(milliseconds: 600),
  }) async {
    // 已连接时「冻结」连接前测得的延迟：探测包会走隧道（你→VPN节点→目标节点），
    // 导致其他节点延迟暴涨且失真。连接期间不重测，沿用连接前的值。
    if (isConnected) return;
    // 用 TCP 握手 RTT 测可达性/延迟：对 nginx(AWG 节点 443) 和 Reality(sing-box 节点 443)
    // 都有效——而原来的 HTTPS GET /vpn-api/health 对 Reality 节点必失败(443 是裸 TCP 不是
    // HTTP)，导致 sing-box 节点永远测不到延迟、误显示离线。只连一下即断，纯测 1 个 RTT。
    for (int r = 0; r < rounds; r++) {
      await Future.wait(servers.map((s) async {
        try {
          final sw = Stopwatch()..start();
          final sock = await Socket.connect(s.relayHost, 443,
              timeout: const Duration(seconds: 2));
          sw.stop();
          sock.destroy();
          s.addLatencySample(sw.elapsedMilliseconds);
        } catch (_) {
          s.addLatencySample(null);
        }
        notifyListeners();
      }));
      if (r < rounds - 1) await Future.delayed(gap);
    }
  }

  // ── 智能分配：综合「延迟 70% + 负载 30%」打分，选最优节点 ──────────
  // 仅在候选含真实(可连)节点时有意义；offline / display-only 不参与。
  ServerConfig? pickAutoServer(List<ServerConfig> servers) {
    final cands = servers
        .where((s) => !s.isDisplayOnly && s.status != 'offline')
        .toList();
    if (cands.isEmpty) {
      final real = servers.where((s) => !s.isDisplayOnly).toList();
      return real.isEmpty ? null : real.first;
    }
    double scoreOf(ServerConfig s) {
      // 延迟归一化到 0–1（以 300ms 为满刻度；无样本按最差 300 计）。
      final lat = (s.latencyMs ?? 300).clamp(0, 300) / 300.0;
      final load = s.loadPercent.clamp(0, 100) / 100.0;
      return 0.7 * lat + 0.3 * load;   // 越小越好
    }
    cands.sort((a, b) => scoreOf(a).compareTo(scoreOf(b)));
    return cands.first;
  }

  /// 智能分配并连接（先快速测一轮延迟以便评分）。
  Future<void> connectAuto(List<ServerConfig> servers) async {
    await setAutoSelect(true);
    // 【提速】不再同步测速阻塞连接 —— 原来这里 await measureLatencies 要对每个节点 TCP 连
    // 443、超时 3s，Future.wait 等最慢的那个,境外/有离线节点时整整几秒都耗在点连接之前(没被
    // _connectSw 计到)。改用列表页/启动时已测好的延迟样本直接挑(pickAutoServer 无样本时按
    // 负载也能挑),立即连接;测速丢后台刷新供下次用。
    final best = pickAutoServer(servers);
    if (best == null) {
      _error = _isZh() ? '暂无可用节点' : 'No nodes available';
      notifyListeners();
      return;
    }
    measureLatencies(servers, rounds: 1);   // 后台刷新,不 await
    await connect(best);
  }

  /// 记录用户的「智能 / 手动」偏好。手动选具体节点时传 false。
  Future<void> setAutoSelect(bool v) async {
    _autoSelect = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_select', v);
  }

  /// 记录用户的「连接模式」偏好（自动/快速/强力/超级）。
  /// 若当前已连接，立即按新模式重连，方便即时切换/测试。
  Future<void> setConnMode(ConnMode m) async {
    if (_connMode == m) return;
    _connMode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conn_mode', m.name);
    // 已连接 → 用同一节点按新模式重连。
    final s = _activeServer;
    if (isConnected && s != null && !s.isDisplayOnly) {
      await disconnect();
      await connect(s);
    }
  }

  /// 「连接模式」本地化名称。
  String connModeLabel(ConnMode m, bool zh) {
    switch (m) {
      case ConnMode.auto:       return zh ? '自动' : 'Auto';
      case ConnMode.direct:     return zh ? '快速' : 'Fast';
      case ConnMode.relay:      return zh ? '强力' : 'Strong';
      case ConnMode.cloudflare: return zh ? '超级' : 'Ultra';
    }
  }

  String get elapsedFormatted {
    final s   = _elapsedSecs ?? 0;
    final h   = s ~/ 3600;
    final m   = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  // ── 本地用量计量实现（#8）────────────────────────────────────
  // 用量在本地累计（隧道适配器 rx+tx 增量），上限由服务器下发；按 UTC 日重置。
  Future<void> _loadUsage() async {
    final prefs = await SharedPreferences.getInstance();
    _usageDay  = prefs.getString('usage_day') ?? _utcDay();
    _dailyUsed = prefs.getInt('usage_bytes') ?? 0;
    _rollDayIfNeeded();
  }

  Future<void> _persistUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usage_day', _usageDay);
    await prefs.setInt('usage_bytes', _dailyUsed);
  }

  void _rollDayIfNeeded() {
    final today = _utcDay();
    if (_usageDay != today) {
      _usageDay  = today;
      _dailyUsed = 0;
      _persistUsage();
    }
  }

  /// 流量上限（仅展示用，不做强制；试用强制由时间额度负责）。
  void setDailyQuota(int? bytes) {
    _quotaBytes = bytes;
    _rollDayIfNeeded();
    notifyListeners();
  }

  void _startUsagePolling() {
    _usageTimer?.cancel();
    _rollDayIfNeeded();
    _pollUsage();   // 立即建立基线
    _usageTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollUsage());
  }

  Future<void> _stopUsagePolling() async {
    _usageTimer?.cancel();
    _usageTimer = null;
    await _pollUsage();   // 结算最后一段
  }

  /// 最近一次 ensurePeer（在目标服务器上确保本机 peer 存在）的结果。
  bool? _lastEnsurePeerOk;

  /// Apple 隧道诊断串（错误信息弹窗展示）：收发字节 + 最后握手时间。
  /// 握手「从未」= UDP 根本没通到服务器，此时即便界面显示已连接也不会有流量。
  String? tunnelDiagnostic;

  Timer? _diagTimer;

  /// 隧道一建立就开始采集诊断（不等连通性验证——验证失败时更需要这份数据）。
  void _startDiagPolling() {
    _diagTimer?.cancel();
    _updateTunnelDiagnostic();
    _diagTimer = Timer.periodic(const Duration(seconds: 5), (_) => _updateTunnelDiagnostic());
  }

  void _stopDiagPolling() {
    _diagTimer?.cancel();
    _diagTimer = null;
  }

  /// 供「错误信息」弹窗主动拉取一次最新诊断。
  Future<String?> refreshTunnelDiagnostic() async {
    await _updateTunnelDiagnostic();
    return tunnelDiagnostic;
  }

  Future<void> _updateTunnelDiagnostic() async {
    // 纯 sing-box 客户端：AWG 的 iOS 内核诊断已移除；sing-box 诊断留待后续按需补。
    return;
  }

  static String _fmtBytes(int b) {
    if (b < 0) return '?';
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  Future<void> _pollUsage() async {
    // 取 rx/tx 分项：rx=下行(收)、tx=上行(发)。隧道未起/平台不支持返回 [-1,-1]。
    final rxtx = await _engine.transferRxTx()
        .timeout(const Duration(seconds: 3), onTimeout: () => const [-1, -1]);
    unawaited(_updateTunnelDiagnostic());
    _rollDayIfNeeded();
    final rx = rxtx.isNotEmpty ? rxtx[0] : -1;
    final tx = rxtx.length > 1 ? rxtx[1] : -1;
    if (rx < 0 || tx < 0) { _downBps = 0; _upBps = 0; return; }

    // 速率 = 增量 / 时间间隔
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastRx >= 0 && _lastSpeedMs > 0) {
      final dt = (nowMs - _lastSpeedMs) / 1000.0;
      if (dt >= 0.5) {
        final dRx = rx - _lastRx, dTx = tx - _lastTx;
        _downBps = dRx > 0 ? (dRx / dt).round() : 0;
        _upBps   = dTx > 0 ? (dTx / dt).round() : 0;
        _lastRx = rx; _lastTx = tx; _lastSpeedMs = nowMs;
      }
    } else {
      _lastRx = rx; _lastTx = tx; _lastSpeedMs = nowMs;
    }

    // 今日总用量（rx+tx）
    final total = rx + tx;
    if (_statsBaseline == null) { _statsBaseline = total; notifyListeners(); return; }
    var delta = total - _statsBaseline!;
    if (delta < 0) delta = total;          // 计数归零（隧道重启）
    _statsBaseline = total;
    if (delta > 0) { _dailyUsed += delta; _persistUsage(); }
    notifyListeners();
  }

  // ── 时间试用实现（#3）+ 看广告延长（#4）─────────────────────────
  // 用文件 + 强制 flush 落盘，避免任务管理器强杀（后台进程被冻结）时
  // SharedPreferences 的 apply() 异步写入还没落盘就丢失，导致额度/奖励重置。
  File? _trialFile;
  Future<File> _getTrialFile() async {
    if (_trialFile != null) return _trialFile!;
    final dir = await getApplicationSupportDirectory();
    _trialFile = File('${dir.path}/trial.json');
    return _trialFile!;
  }

  Future<void> _loadTrial() async {
    try {
      final f = await _getTrialFile();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _trialDay     = (m['day'] as String?) ?? _utcDay();
        _trialStartMs = (m['startMs'] as num?)?.toInt();
        _adBonusSec   = (m['bonusSec'] as num?)?.toInt() ?? 0;
      } else {
        // 迁移：旧版本存在 SharedPreferences 里
        final prefs = await SharedPreferences.getInstance();
        _trialDay     = prefs.getString('trial_day') ?? _utcDay();
        _trialStartMs = prefs.getInt('trial_start_ms');
        _adBonusSec   = prefs.getInt('trial_bonus_sec') ?? 0;
        await _persistTrial();   // 落到文件
      }
    } catch (_) {
      _trialDay = _utcDay();
    }
    _trialLoaded = true;        // 加载完成后才允许跨日滚动
    _rollTrialDayIfNeeded();
    _recomputeTrial();
  }

  Future<void> _persistTrial() async {
    // 双写：SharedPreferences + 文件(flush 落盘)，任一存活即可。
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trial_day', _trialDay);
      if (_trialStartMs == null) {
        await prefs.remove('trial_start_ms');
      } else {
        await prefs.setInt('trial_start_ms', _trialStartMs!);
      }
      await prefs.setInt('trial_bonus_sec', _adBonusSec);
    } catch (_) {}
    try {
      final f = await _getTrialFile();
      await f.writeAsString(
        jsonEncode({'day': _trialDay, 'startMs': _trialStartMs, 'bonusSec': _adBonusSec}),
        flush: true,   // 强制落盘 → 强杀也不丢
      );
    } catch (_) {}
  }

  /// App 切后台/即将退出时调用：把试用状态最后强制保存一次（冻结/强杀前最后机会）。
  Future<void> saveTrialState() => _persistTrial();

  void _rollTrialDayIfNeeded() {
    // 加载完成前绝不滚动/清零（否则启动竞态会把默认空日期当成「新的一天」，
    // 把看广告奖励和起点清零并写回磁盘，覆盖已保存的好数据 → 永远 30 分钟）。
    if (!_trialLoaded) return;
    final today = _utcDay();
    if (_trialDay != today) {
      _trialDay      = today;
      _trialStartMs  = null;     // 次日重新开始一轮
      _adBonusSec    = 0;
      _trialExceeded = false;
      _persistTrial();
    }
  }

  /// 服务器下发的每日试用秒数（null = 无限/付费）。AuthProvider 配置变化时调用。
  void setTimeQuota(int? seconds) {
    _timeLimitSec = seconds;
    _rollTrialDayIfNeeded();
    _ensureTrialTicker();   // 额度到位后确保倒计时在跑
    _recomputeTrial();
    notifyListeners();
  }

  // 连接成功即记录倒计时起点并【立即持久化】——不依赖额度(_timeLimitSec)是否已就绪，
  // 否则首连时若配置还没拉回来就会漏记起点，导致下次启动倒计时从头开始(#2)。
  // 付费用户(_timeLimitSec=null)只是记录起点不展示/不限制，无副作用。
  void _startTrialTracking() {
    _rollTrialDayIfNeeded();
    if (_trialStartMs == null) {
      _trialStartMs = DateTime.now().millisecondsSinceEpoch;
      _persistTrial();   // 起点一确定就落盘
    }
    _trialTimer?.cancel();
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) => _recomputeTrial());
    _recomputeTrial();
  }

  // 计算剩余、刷新 UI、用尽则强制断开。
  void _recomputeTrial() {
    if (_timeLimitSec == null) { _trialExceeded = false; return; }
    _rollTrialDayIfNeeded();
    final exhausted = _trialStartMs != null && trialRemainingSec <= 0;
    if (exhausted && !_trialExceeded) {
      _trialExceeded = true;
      debugPrint('[VPN] 今日免费试用时长已用尽，强制断开系统 VPN');
      _forceStopOnQuota();   // 无条件停原生隧道（部分机型 app 状态可能不是 connected）
    }
    notifyListeners();
  }

  // 额度用尽时强制拆隧道：不依赖 app 当前状态，直接停原生 VPN + 中继，确保系统
  // 状态栏的 VPN 真正断开（修复三星上「app 显示已断、系统 VPN 仍连着」）。
  Future<void> _forceStopOnQuota() async {
    _userInitiatedDisconnect = true;   // 用尽后禁止任何自动回退
    _trialTimer?.cancel();             // 已用尽，停止 1s 轮询
    _stopConnectedPing();
    try {
      await _engine.stop().timeout(const Duration(seconds: 6), onTimeout: () {});
    } catch (_) {}
    _status   = VpnStatus.disconnected;
    notifyListeners();
  }

  // ── 看广告解锁：需累计满 kAdRequiredSec 秒（连播多条，无需用户反复点）──────
  // 目标约 60s，但放满 50s 即视为达标发放（广告时长不可控，避免为凑满而多放一条）。
  static const int kAdRequiredSec = 50;
  int _adProgressSec = 0;
  int get adProgressSec => _adProgressSec;
  int get adRequiredSec => kAdRequiredSec;

  /// 累计本次广告观看秒数；满 kAdRequiredSec 秒才发放 +kAdRewardMinutes 并清零。返回 true=已发放。
  Future<bool> addAdWatch(int watchedSec) async {
    if (watchedSec <= 0) { notifyListeners(); return false; }
    _adProgressSec += watchedSec;
    if (_adProgressSec >= kAdRequiredSec) {
      _adProgressSec = 0;
      await addAdBonusMinutes(kAdRewardMinutes);
      return true;
    }
    notifyListeners();
    return false;
  }

  /// 看完一条激励视频 → 增加奖励时长。立即生效，可解除「已用尽」。
  /// 关键修复：**重新锚定起点**，让"剩余时长 = 当前剩余(已 clamp≥0) + 奖励"，
  /// 避免断开期间墙钟跑太久把 elapsed 撑到远超额度，导致看广告加的时间被淹没（剩余永远 0）。
  Future<void> addAdBonusMinutes(int minutes) async {
    _rollTrialDayIfNeeded();
    final bonus = minutes * 60;
    if (_trialStartMs == null) {
      // 还没开始计时：直接加进奖励池即可。
      _adBonusSec += bonus;
    } else {
      final curRemain = trialRemainingSec;          // 已 clamp ≥ 0
      _adBonusSec += bonus;
      final desired = curRemain + bonus;            // 目标剩余
      // 令 trialTotalSec - elapsed == desired  →  startMs = now - (total - desired)*1000
      _trialStartMs = DateTime.now().millisecondsSinceEpoch - (trialTotalSec - desired) * 1000;
    }
    _trialExceeded = false;
    await _persistTrial();
    notifyListeners();
  }

  String get trialRemainingFormatted {
    final s = trialRemainingSec;
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _usageTimer?.cancel();
    _diagTimer?.cancel();
    _trialTimer?.cancel();
    _pingTimer?.cancel();
    _stageSub?.cancel();
    _timer?.cancel();
    // 注意：销毁时【不】拆隧道。返回键/切后台/被系统回收都应保持 VPN 运行，
    // 下次打开自动采纳；仅右上角「退出」键通过 disconnect() 主动断开。
    super.dispose();
  }
}
