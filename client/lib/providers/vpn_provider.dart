import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart'; // PlatformException + rootBundle
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../vpn/vpn_engine.dart';
import '../vpn/amnezia_wg_engine.dart';
import '../models/server_config.dart';
import '../services/ws_relay_service.dart';
import '../services/port_hopping.dart';
import '../services/api_service.dart';
import '../brand.dart';
import '../env.dart';

export 'package:amneziawg_flutter/amneziawg_flutter.dart' show VpnStage;

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

class VpnProvider extends ChangeNotifier {
  // VPN 引擎(引擎无关抽象)。当前只有 AmneziaWG;sing-box 之后按节点 tier 切换。
  final VpnEngine _engine = AmneziaWgEngine();

  /// 连接前需要停掉的另一条隧道（共享节点 sing-box）。由 app 层注入，实现系统级互斥。
  Future<void> Function()? onBeforeConnect;

  VpnStatus     _status        = VpnStatus.disconnected;
  ServerConfig? _activeServer;
  /// 用户上次选择的是「智能分配」(true) 还是某台具体节点(false)。持久化。
  bool          _autoSelect    = true;
  bool   get autoSelect => _autoSelect;
  int?          _elapsedSecs;
  String?       _error;
  Timer?        _timer;
  Timer?        _fallbackTimer;
  StreamSubscription<VpnStage>? _stageSub;

  VpnProtocol        _protocol         = VpnProtocol.direct;
  ConnMode           _connMode         = ConnMode.auto;   // 用户「连接模式」偏好
  bool               _switchingToRelay = false;
  // 用户主动断开标志：置位后，任何挂起的连通性探测/回退计时器都不得再发起
  // 新的连接尝试（修复「手动断开后又自动切到下一模式」）。connect() 清零。
  bool               _userInitiatedDisconnect = false;
  final WsRelayService _relay          = WsRelayService();

  RoutingMode        _routingMode      = RoutingMode.global;
  List<String>?      _cachedNonCnRoutes;   // 懒加载，首次连接时计算并缓存

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
  bool get quotaExceeded  => _trialExceeded;

  static String _utcDay() => DateTime.now().toUtc().toIso8601String().substring(0, 10);

  // 任何挂起的异步流程（探测/回退）遇到以下情况都应中止
  bool get _aborted =>
      _userInitiatedDisconnect ||
      _status == VpnStatus.disconnecting ||
      _status == VpnStatus.disconnected;

  static bool _isZh() => Platform.localeName.toLowerCase().startsWith('zh');

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
    if (saved == RoutingMode.smart.name) {
      _routingMode = RoutingMode.smart;
      notifyListeners();
    } else if (saved == RoutingMode.global.name) {
      _routingMode = RoutingMode.global;
      notifyListeners();
    } else if (Brand.isZh) {
      _routingMode = RoutingMode.smart;   // 中文首次默认智能
      notifyListeners();
    }
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
    _cachedNonCnRoutes = null; // 切换模式时清除缓存，强制重新计算
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('routing_mode', mode.name);
  }

  void _onStage(VpnStage stage) {
    switch (stage) {
      case VpnStage.connected:
        // 隧道接口已 UP，但流量未必通。一律先保持「连接中」，等连通性验证
        // 通过后再由 _postConnectCheck / _postRelayCheck 置为 connected（#5）。
        if (_userInitiatedDisconnect) break;  // 用户已断开，忽略迟到的 connected
        if (_switchingToRelay) {
          _fallbackTimer?.cancel();
          _switchingToRelay = false;
          _status = VpnStatus.connecting;
          _postRelayCheck(_activeServer);   // 5 秒后验证中继流量
        } else {
          _status = VpnStatus.connecting;
          _postConnectCheck(_activeServer); // 4 秒后验证直连流量
        }
      case VpnStage.connecting:
        _status = VpnStatus.connecting;
      case VpnStage.disconnected:
        _status = VpnStatus.disconnected;
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
    // 免费时长已用尽：禁止任何新连接（不管从主页还是节点列表点的）。#1
    if (_trialExceeded) {
      _error  = _isZh()
          ? '免费时长已用完，看广告或升级后再连接'
          : 'Free time used up. Watch an ad or upgrade to connect.';
      _status = VpnStatus.disconnected;
      notifyListeners();
      return;
    }
    // 系统级只允许一条隧道：连 WireGuard 前先停掉共享节点(sing-box)。
    try { await onBeforeConnect?.call(); } catch (_) {}
    _error            = null;
    _status           = VpnStatus.connecting;
    _activeServer     = server;
    _protocol         = VpnProtocol.direct;
    _switchingToRelay = false;
    _userInitiatedDisconnect = false;  // 新的连接尝试，解除断开锁
    _fallbackTimer?.cancel();
    _sessionPort      = null;   // 用户主动连接 = 一次重连，按当前时间重新算端口
    _statsBaseline    = null;   // 新隧道，用量基线重置（首个轮询重新建立基线）
    notifyListeners();

    try {
      // 0. 按需建 peer：确保该节点服务器上已添加本设备（on-demand provisioning）。
      //    尽力而为，不阻断连接（多数情况已由列表预热提前建好）。
      if (!server.isDisplayOnly) {
        await ApiService.instance.ensurePeer(serverIds: [server.id]);
      }

      // 强制连接模式：强力/超级 跳过直连，直接走对应中继。
      if (_connMode == ConnMode.relay || _connMode == ConnMode.cloudflare) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_server_id', server.id);
        } catch (_) {}
        if (_connMode == ConnMode.cloudflare) {
          final cfUrl = server.cfRelayUrl;
          // 该节点无 Cloudflare 线路时退回强力(wstunnel)。
          await _switchToRelay(server,
              relayBaseUrl: (cfUrl != null && cfUrl.isNotEmpty)
                  ? cfUrl
                  : 'wss://${server.relayHost}',
              force: true);
        } else {
          await _switchToRelay(server,
              relayBaseUrl: 'wss://${server.relayHost}', force: true);
        }
        return;
      }

      // 1. 计算实际连接端口（端口跳变 or 固定端口），并钉死到本次会话。
      //    端口只在此处基于时间计算一次；连上后整个会话不再改变。
      final effectivePort = _computePort(server);
      _sessionPort = effectivePort;

      // 2. 将 AWG 配置中的端点端口替换为跳变端口
      String wgConf = _routingMode == RoutingMode.smart
          ? await _applySmartRouting(server.wgConf, excludeIp: null)
          : server.wgConf;
      wgConf = PortHoppingService.instance
          .rewriteEndpointPort(wgConf, effectivePort);

      debugPrint('[VPN] 直连 AmneziaWG，端口=$effectivePort');

      await _engine.start(EngineStartParams(
        serverAddress:  '${server.endpoint}:$effectivePort',
        wgQuickConfig:  wgConf,
        providerBundle: kProviderBundle,
      ));

      // 直连兜底：到时仍未确认连通 → 切换 wstunnel 443 中继（层 2）。
      // 16s 给 _postConnectCheck 的多次探测（约 4+5+1+5s）留足时间，避免
      // 在直连其实可用、只是数据面稍慢稳定时被过早切走。
      // 使用 relayHost（域名）而非 endpoint（可能为 IP），确保 TLS 证书匹配。
      // 仅「自动」模式下才在直连超时后降级；「快速」模式只直连，不降级。
      if (_connMode == ConnMode.auto) {
        _fallbackTimer = Timer(
          const Duration(seconds: 16),
          () => _switchToRelay(server, relayBaseUrl: 'wss://${server.relayHost}'),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_server_id', server.id);
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

  /// 计算端口（端口跳变 or 固定端口）。
  ///
  /// 本次会话已钉死端口时（_sessionPort 非空）直接复用，确保连接建立后
  /// 即便 connect() 被再次进入（如断线自动重连）也不会跨小时窗口换端口。
  /// 只有在主动 disconnect() 清空 _sessionPort 后，才会重新基于时间计算。
  int _computePort(ServerConfig server) {
    if (_sessionPort != null) return _sessionPort!;
    if (server.portSecret == null || server.portSecret!.isEmpty) {
      return server.port;
    }
    // 尝试当前 hour，连通性验证失败后 fallback 到 wstunnel，不在此处遍历 ±1
    return PortHoppingService.instance
        .computePort(server.portSecret!, hourOffset: 0);
  }

  // AWG 在服务器上的内部监听端口（wstunnel --restrict-to 匹配此端口）。
  // 注意：server.port 是对外暴露的端口（可能经过 iptables DNAT），
  // 而 wstunnel 直接连接 AWG 内部端口（不经过 DNAT），因此必须用固定值 51820。
  static const int _awgInternalPort = 51820;

  // ── 中继回退（层 2 = wstunnel 443，层 3 = Cloudflare Tunnel）─────────────────
  //
  // [relayBaseUrl]  中继服务器 WebSocket 基础 URL，不含路径（如 wss://host.com）
  //                 ws_relay_service 会自动追加 /secure-tunnel/v1/events
  // [force]         true = 由连通性验证失败强制触发
  //
  Future<void> _switchToRelay(
    ServerConfig server, {
    required String relayBaseUrl,
    bool force = false,
  }) async {
    // 立即取消定时器：防止 _postConnectCheck 和定时器同时触发时的竞争条件
    // （两者都可能在 T≈12s 时触发，并发调用会导致 _localPort 被清零后再 ! 解引用）
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    // 用户已主动断开：绝不再自动尝试下一模式（#4）。
    if (_userInitiatedDisconnect || _aborted) return;
    if (!force && _status == VpnStatus.connected) return; // 直连已成功，无需切换

    final primaryBase = 'wss://${server.relayHost}';
    final isCf        = relayBaseUrl != primaryBase;
    debugPrint('[VPN] 切换到${isCf ? ' Cloudflare' : ' wstunnel-443'} 中继: $relayBaseUrl');

    _switchingToRelay = true;
    // 强力模式 = wstunnel 443；暴力模式 = Cloudflare（#3）
    _protocol         = isCf ? VpnProtocol.cloudflare : VpnProtocol.relay;
    _status           = VpnStatus.connecting;
    _error            = null;
    notifyListeners();

    // 停止正在进行的隧道
    try { await _engine.stop(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));

    // 解析服务器 IP，用于在 AllowedIPs 中排除（防止 WebSocket 中继回环）
    String? serverIp;
    try {
      final addrs = await InternetAddress.lookup(server.endpoint)
          .timeout(const Duration(seconds: 5));
      serverIp = addrs
          .firstWhere((a) => a.type == InternetAddressType.IPv4,
              orElse: () => addrs.first)
          .address;
      debugPrint('[VPN] 服务器 IP 解析成功: $serverIp');
    } catch (e) {
      debugPrint('[VPN] 服务器 IP 解析失败，使用子网回退模式: $e');
    }

    try {
      // ws_relay_service 追加 /v1/events；nginx 代理 /secure-tunnel/ → wstunnel
      // JWT 中的 rp 必须等于 AWG 内部监听端口（51820），与 wstunnel --restrict-to 一致。
      // server.port 是对外暴露端口（可能经 iptables DNAT），不适合此处。
      final localPort = await _relay.start(
          '$relayBaseUrl/secure-tunnel', _awgInternalPort);
      final relayConf = await _buildRelayConf(server.wgConf, localPort, serverIp);

      await _engine.start(EngineStartParams(
        serverAddress:  '127.0.0.1:$localPort',
        wgQuickConfig:  relayConf,
        providerBundle: kProviderBundle,
      ));

      // 等 20 秒确认连通；超时则尝试下一层
      _fallbackTimer = Timer(const Duration(seconds: 20), () async {
        if (_status != VpnStatus.connected) {
          await _relay.stop();
          final cfUrl = server.cfRelayUrl;
          if (_connMode == ConnMode.auto && !isCf && cfUrl != null) {
            // 层 3：wstunnel-443 超时 → 尝试 Cloudflare Tunnel（仅自动模式降级）
            await _switchToRelay(server, relayBaseUrl: cfUrl, force: true);
          } else {
            // 所有层均失败
            _error  = '无法连接到 VPN（全部线路尝试失败，请检查网络后重试）';
            _status = VpnStatus.error;
            notifyListeners();
          }
        }
      });
    } on PlatformException catch (e) {
      await _relay.stop();
      _error  = e.message ?? e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    } catch (e) {
      await _relay.stop();
      _error  = '中继连接失败: $e';
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  /// 将直连配置改写为中继模式配置。
  ///
  /// 路由策略：
  ///   A) serverIp 已解析（正常情况）→ 全隧道模式
  ///      AllowedIPs = 0.0.0.0/0 排除 serverIp/32
  ///      - 所有流量（含 DNS）走 VPN，由 VPN 服务器代理访问互联网
  ///      - WebSocket 中继流量发往 serverIp → 走物理网卡 → 不回环
  ///      - DNS 走 VPN 隧道，不存在污染问题，无需修改 DNS 配置
  ///
  ///   B) serverIp 解析失败（极少见）→ 子网回退模式
  ///      AllowedIPs = VPN 子网（10.200.0.0/24）
  ///      - 仅 VPN 内网流量走隧道，互联网流量走物理网卡
  ///      - DNS 走物理网卡，国内 DNS 会污染境外域名
  ///      - 降级为国内 DNS（114.114.114.114）以保证基本可用
  Future<String> _buildRelayConf(String wgConf, int relayPort, String? serverIp) async {
    // 1. Endpoint 改为本地中继端口
    var conf = wgConf.replaceAll(
      RegExp(r'Endpoint\s*=\s*\S+'),
      'Endpoint     = 127.0.0.1:$relayPort',
    );

    // 2. AllowedIPs（根据路由模式 + serverIp 可用性决定）
    String allowedIps;
    if (serverIp != null) {
      if (_routingMode == RoutingMode.smart) {
        // 智能模式：排除中国IP + 服务器IP（防 WebSocket 中继回环）
        final routes = await _getSmartRoutes(excludeIp: serverIp);
        allowedIps = routes.join(', ');
      } else {
        // 全局模式：0.0.0.0/0 排除服务器IP
        allowedIps = _ipv4AllExcept(serverIp).join(', ');
      }
    } else {
      // 无法解析服务器 IP → 退化为仅路由 VPN 子网
      final addrMatch = RegExp(r'Address\s*=\s*([\d.]+)/').firstMatch(conf);
      final vpnSubnet = addrMatch != null
          ? '${addrMatch.group(1)!.split('.').take(3).join('.')}.0/24'
          : '10.200.0.0/24';
      allowedIps = vpnSubnet;
      // 子网模式下 DNS 走物理网卡，必须用国内 DNS 否则境外域名被污染
      conf = _setDns(conf, '114.114.114.114, 223.5.5.5');
    }
    conf = conf.replaceAll(
      RegExp(r'AllowedIPs\s*=\s*[^\n]+'),
      'AllowedIPs   = $allowedIps',
    );

    return conf;
  }

  // ── 智能路由：将 AWG 配置的 AllowedIPs 改为非中国IP段 ────────────────────
  Future<String> _applySmartRouting(String wgConf, {required String? excludeIp}) async {
    final routes = await _getSmartRoutes(excludeIp: excludeIp);
    return wgConf.replaceAll(
      RegExp(r'AllowedIPs\s*=\s*[^\n]+'),
      'AllowedIPs   = ${routes.join(', ')}',
    );
  }

  /// 获取智能模式的 AllowedIPs 列表（非中国IP段，可选排除指定IP）。
  /// 结果在会话内缓存，切换模式时自动清除。
  Future<List<String>> _getSmartRoutes({required String? excludeIp}) async {
    if (_cachedNonCnRoutes == null) {
      final text = await rootBundle.loadString('assets/routes/cn_cidr.txt');
      final cnCidrs = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      _cachedNonCnRoutes = _computeComplementCidrs(cnCidrs);
      debugPrint('[VPN] 智能路由：加载 ${cnCidrs.length} 条中国IP段，计算 ${_cachedNonCnRoutes!.length} 条 AllowedIPs');
    }

    if (excludeIp == null) return _cachedNonCnRoutes!;

    // 从已有路由中再排除服务器IP（防中继回环）
    return _subtractIp(_cachedNonCnRoutes!, excludeIp);
  }

  /// 计算 CIDR 列表的互补集（全 IPv4 空间 MINUS 给定 CIDRs）。
  static List<String> _computeComplementCidrs(List<String> excludeCidrs) {
    // 1. 解析为 (start, end) 闭区间
    final ranges = <(int, int)>[];
    for (final cidr in excludeCidrs) {
      final slash = cidr.indexOf('/');
      if (slash < 0) continue;
      final ipParts = cidr.substring(0, slash).split('.');
      if (ipParts.length != 4) continue;
      try {
        final ip     = (int.parse(ipParts[0]) << 24) |
                       (int.parse(ipParts[1]) << 16) |
                       (int.parse(ipParts[2]) << 8)  |
                        int.parse(ipParts[3]);
        final prefix = int.parse(cidr.substring(slash + 1));
        final mask   = prefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - prefix)) - 1));
        final start  = ip & mask;
        final size   = prefix == 0 ? 0x100000000 : (1 << (32 - prefix));
        ranges.add((start, start + size - 1));
      } catch (_) { continue; }
    }

    // 2. 排序 + 合并重叠区间
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isEmpty || r.$1 > merged.last.$2 + 1) {
        merged.add(r);
      } else {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      }
    }

    // 3. 收集"空隙"作为结果
    final result = <String>[];
    int cursor   = 0;
    for (final (start, end) in merged) {
      if (cursor < start) result.addAll(_rangeToCidrs(cursor, start - 1));
      cursor = end + 1;
      if (cursor > 0xFFFFFFFF) break;
    }
    if (cursor <= 0xFFFFFFFF) result.addAll(_rangeToCidrs(cursor, 0xFFFFFFFF));
    return result;
  }

  /// 从 CIDR 列表中裁减掉单个 /32 IP（用于排除 VPN 服务器IP）。
  static List<String> _subtractIp(List<String> cidrs, String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return cidrs;
    final target = (int.parse(parts[0]) << 24) |
                   (int.parse(parts[1]) << 16) |
                   (int.parse(parts[2]) << 8)  |
                    int.parse(parts[3]);

    final result = <String>[];
    for (final cidr in cidrs) {
      final slash   = cidr.indexOf('/');
      if (slash < 0) { result.add(cidr); continue; }
      final ipParts = cidr.substring(0, slash).split('.');
      if (ipParts.length != 4) { result.add(cidr); continue; }
      try {
        final netIp  = (int.parse(ipParts[0]) << 24) |
                       (int.parse(ipParts[1]) << 16) |
                       (int.parse(ipParts[2]) << 8)  |
                        int.parse(ipParts[3]);
        final prefix = int.parse(cidr.substring(slash + 1));
        final mask   = prefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - prefix)) - 1));
        if ((target & mask) != (netIp & mask)) {
          result.add(cidr); // target 不在此 CIDR 中，直接保留
        } else {
          // target 在此 CIDR 中，用 _ipv4AllExcept 拆分
          result.addAll(_ipv4AllExcept(ip).where((r) {
            // 只保留与原 CIDR 交集的部分（防止拆分超出原范围）
            final rSlash  = r.indexOf('/');
            final rParts  = r.substring(0, rSlash).split('.');
            final rIp     = (int.parse(rParts[0]) << 24) |
                            (int.parse(rParts[1]) << 16) |
                            (int.parse(rParts[2]) << 8)  |
                             int.parse(rParts[3]);
            final rPrefix = int.parse(r.substring(rSlash + 1));
            final rMask   = rPrefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - rPrefix)) - 1));
            // r 的网络地址必须在原 CIDR 内
            return (rIp & mask) == (netIp & mask);
          }));
        }
      } catch (_) { result.add(cidr); }
    }
    return result;
  }

  /// 将连续 IP 区间 [start, end] 拆分为最精简的 CIDR 列表。
  static List<String> _rangeToCidrs(int start, int end) {
    if (start > end) return [];
    final cidrs = <String>[];
    int curr = start;
    while (curr <= end) {
      int prefix = 32;
      for (int p = 0; p <= 32; p++) {
        final blockSize = p == 0 ? 0x100000000 : (1 << (32 - p));
        if (curr % blockSize == 0 && curr + blockSize - 1 <= end) {
          prefix = p;
          break;
        }
      }
      cidrs.add('${_intToIp(curr)}/$prefix');
      final blockSize = prefix == 0 ? 0x100000000 : (1 << (32 - prefix));
      curr = curr + blockSize;
      if (curr > 0xFFFFFFFF) break;
    }
    return cidrs;
  }

  /// 替换或插入 WireGuard 配置中的 DNS 行
  static String _setDns(String conf, String dnsServers) {
    final line = 'DNS          = $dnsServers';
    if (conf.contains(RegExp(r'^\s*DNS\s*=', multiLine: true))) {
      return conf.replaceAll(
          RegExp(r'^\s*DNS\s*=\s*[^\n]+', multiLine: true), line);
    }
    return conf.replaceFirst(RegExp(r'\[Peer\]'), '$line\n\n[Peer]');
  }

  /// 计算覆盖整个 IPv4 地址空间但排除指定 /32 的 CIDR 列表（共 32 条）。
  static List<String> _ipv4AllExcept(String excludeIp) {
    final parts = excludeIp.split('.');
    if (parts.length != 4) return ['0.0.0.0/0'];

    final target = ((int.tryParse(parts[0]) ?? 0) & 0xFF) << 24 |
                   ((int.tryParse(parts[1]) ?? 0) & 0xFF) << 16 |
                   ((int.tryParse(parts[2]) ?? 0) & 0xFF) << 8  |
                   ((int.tryParse(parts[3]) ?? 0) & 0xFF);

    final routes = <String>[];
    for (int pl = 0; pl < 32; pl++) {
      final bitPos  = 31 - pl;
      final bit     = (target >> bitPos) & 1;
      final prefix  = pl == 0 ? 0 : ((0xFFFFFFFF << (32 - pl)) & 0xFFFFFFFF);
      final sibling = (target & prefix) | ((1 - bit) << bitPos);
      final netMask = (0xFFFFFFFF << (32 - (pl + 1))) & 0xFFFFFFFF;
      routes.add('${_intToIp(sibling & netMask)}/${pl + 1}');
    }
    return routes;
  }

  static String _intToIp(int n) =>
      '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';

  // ── 断开 ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;  // 手动断开即断开，禁止任何自动回退（#4）
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
    try { await _relay.stop(); } catch (_) {}
    _protocol = VpnProtocol.direct;
    _status   = VpnStatus.disconnected;   // 明确置为已断开（不依赖 stage 事件）
    notifyListeners();
  }

  // ── 切换服务器 ───────────────────────────────────────────────
  Future<void> switchServer(ServerConfig server) async {
    if (isConnected) await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
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

  // ── 连通性验证（直连模式握手后约 4 秒执行）──────────────────
  // AWG UDP 被 GFW 过滤时，Android VPN 接口仍会报 connected，
  // 但实际流量无法通过。通过请求外网地址判断隧道是否真正打通。
  Future<void> _postConnectCheck(ServerConfig? server) async {
    await Future.delayed(const Duration(seconds: 4));
    // 用户已断开 / 已切换中继，跳过
    if (server == null || _aborted || _protocol != VpnProtocol.direct || _switchingToRelay) return;

    // 直连握手成功后，数据面（路由/防火墙）可能需要一两秒才稳定，首个探测
    // 偶尔会误判为不通。多探测几次再决定，避免把其实可用的直连错误回退到中继。
    bool ok = false;
    for (var attempt = 1; attempt <= 2; attempt++) {
      ok = await _probeConnectivity();
      if (ok) break;
      if (_aborted || _protocol != VpnProtocol.direct || _switchingToRelay) return;
      if (attempt < 2) await Future.delayed(const Duration(seconds: 1));
    }
    if (_aborted) return;

    if (ok) {
      _fallbackTimer?.cancel(); // 流量畅通，取消中继切换计时器
      _status = VpnStatus.connected;   // 验证通过才显示已连接（#5）
      _startUsagePolling();
      _startTrialTracking();
      _startConnectedPing();           // 连上后每 30s 刷新展示延迟
      notifyListeners();
      debugPrint('[VPN] 连通性验证成功，保持直连（快速模式）');
    } else {
      // UDP 握手失败或流量被墙，切换 wstunnel 443 中继（层 2）
      debugPrint('[VPN] 连通性多次验证失败，切换 wstunnel 443 中继');
      await _switchToRelay(
        server,
        relayBaseUrl: 'wss://${server.relayHost}',  // 域名，确保 TLS 匹配
        force: true,
      );
    }
  }

  // ── 连通性验证（中继模式，握手后约 5 秒执行）────────────────
  // 中继模式下 AWG 握手可能成功（ICMP/UDP 层通了），但 WebSocket
  // 出口侧流量仍可能不通（如 wstunnel 路由配置错误）。
  // 5 秒后用同一个 HTTP 204 检测实际网络可达性；
  // 失败则尝试层 3（Cloudflare Tunnel），或报错。
  Future<void> _postRelayCheck(ServerConfig? server) async {
    await Future.delayed(const Duration(seconds: 5));
    // 中继尝试中（relay=强力 / cloudflare=暴力），用户未断开
    if (server == null || _aborted || _protocol == VpnProtocol.direct) return;

    bool ok = false;
    try {
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 8));
      ok = res.statusCode == 204 || res.statusCode < 400;
    } catch (_) {}
    if (_aborted) return;

    if (ok) {
      _status = VpnStatus.connected;   // 验证通过才显示已连接（#5）
      _startUsagePolling();
      _startTrialTracking();
      _startConnectedPing();           // 连上后每 30s 刷新展示延迟
      notifyListeners();
      debugPrint('[VPN] 中继连通性验证成功（$modeLabel）');
    } else {
      debugPrint('[VPN] 中继连通性验证失败，尝试 Cloudflare Tunnel（暴力模式）');
      await _relay.stop();
      final cfUrl = server.cfRelayUrl;
      // 仅当尚未处于 Cloudflare（暴力）模式时才升级，避免无限循环
      if (cfUrl != null && cfUrl.isNotEmpty && _protocol != VpnProtocol.cloudflare) {
        await _switchToRelay(server, relayBaseUrl: cfUrl, force: true);
      } else {
        // 中继也不通且无 Cloudflare 兜底：必须彻底拆除隧道，否则残留的路由表
        // 会把用户全部流量导入死隧道（黑洞），普通用户完全无法理解。
        // 错误态下也一定要清掉路由。
        try { await _engine.stop(); } catch (_) {}
        try { await _relay.stop(); } catch (_) {}
        _protocol = VpnProtocol.direct;
        _error  = _isZh()
            ? '已连接但流量不通，请稍后重试或更换节点'
            : 'Connected but no traffic. Please retry or switch node.';
        _status = VpnStatus.error;
        notifyListeners();
      }
    }
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
    // 用 relayHost（= api_url 域名，证书有效）而非 endpoint：部分节点的 endpoint
    // 是另一个域名/裸 IP，HTTPS 健康检查会一直失败导致 UI 永久转圈（如西班牙节点）。
    Uri urlOf(ServerConfig s) =>
        Uri.parse('https://${s.relayHost}/vpn-api/health');

    // 持久 Client：复用 TCP+TLS 连接（keep-alive）。先「预热」一轮建立连接（丢弃，
    // 不计样本），之后的样本只含 1 个 RTT，避免每次新建连接的 TLS 握手把真实延迟
    // 放大数倍（30ms ping 曾被测成 ~250ms）。
    final client = http.Client();
    try {
      await Future.wait(servers.map((s) async {
        try {
          await client.get(urlOf(s)).timeout(const Duration(seconds: 4));
        } catch (_) {}
      }));
      for (int r = 0; r < rounds; r++) {
        await Future.wait(servers.map((s) async {
          try {
            final sw = Stopwatch()..start();
            await client.get(urlOf(s)).timeout(const Duration(seconds: 3));
            sw.stop();
            s.addLatencySample(sw.elapsedMilliseconds);
          } catch (_) {
            s.addLatencySample(null);
          }
          notifyListeners();
        }));
        if (r < rounds - 1) await Future.delayed(gap);
      }
    } finally {
      client.close();
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
    // 快速单轮测一遍延迟，让评分有数据（不阻塞太久）
    await measureLatencies(servers, rounds: 1);
    final best = pickAutoServer(servers);
    if (best == null) {
      _error = _isZh() ? '暂无可用节点' : 'No nodes available';
      notifyListeners();
      return;
    }
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

  Future<void> _pollUsage() async {
    // 取 rx/tx 分项：rx=下行(收)、tx=上行(发)。隧道未起/平台不支持返回 [-1,-1]。
    final rxtx = await _engine.transferRxTx()
        .timeout(const Duration(seconds: 3), onTimeout: () => const [-1, -1]);
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
    try { await _relay.stop(); } catch (_) {}
    _protocol = VpnProtocol.direct;
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
    _trialTimer?.cancel();
    _pingTimer?.cancel();
    _stageSub?.cancel();
    _timer?.cancel();
    // 注意：销毁时【不】拆隧道。返回键/切后台/被系统回收都应保持 VPN 运行，
    // 下次打开自动采纳；仅右上角「退出」键通过 disconnect() 主动断开。
    super.dispose();
  }
}
