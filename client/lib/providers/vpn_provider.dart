import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // PlatformException + rootBundle
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amneziawg_flutter/amneziawg_flutter.dart';
import '../models/server_config.dart';
import '../services/ws_relay_service.dart';
import '../services/port_hopping.dart';
import '../env.dart';

export 'package:amneziawg_flutter/amneziawg_flutter.dart' show VpnStage;

enum VpnStatus    { disconnected, connecting, connected, disconnecting, error }
/// 连接通道：
/// - [direct]     UDP 直连      → 对外显示「快速模式」
/// - [relay]      wstunnel 443  → 对外显示「强力模式」
/// - [cloudflare] Cloudflare    → 对外显示「暴力模式」
enum VpnProtocol  { direct, relay, cloudflare }
/// 路由模式
/// - [global]：全局模式，所有流量走 VPN（0.0.0.0/0）
/// - [smart] ：智能模式，中国大陆 IP 直连，境外流量走 VPN
enum RoutingMode  { global, smart }

class VpnProvider extends ChangeNotifier {
  VpnStatus     _status        = VpnStatus.disconnected;
  ServerConfig? _activeServer;
  int?          _elapsedSecs;
  String?       _error;
  Timer?        _timer;
  Timer?        _fallbackTimer;
  StreamSubscription<VpnStage>? _stageSub;

  VpnProtocol        _protocol         = VpnProtocol.direct;
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
  String             _usageDay    = '';      // 当前计量所属 UTC 日期 yyyy-mm-dd
  int?               _statsBaseline;         // 上次轮询的隧道累计值，用于求增量
  int?               _quotaBytes;            // 服务器下发的今日上限（仅用于流量展示）
  Timer?             _usageTimer;

  // ── 基于时间的免费试用（#3 + 看广告延长 #4）──────────────────────
  // 免费用户首次连接成功当天记 _trialStartMs，倒计时按【墙钟】连续走，
  // 断开也不停；到期当天禁连，次日(UTC)重置。上限 _timeLimitSec 从服务器拉取，
  // 看激励广告每次 +kAdRewardMinutes 分钟累加到 _adBonusSec。
  int?               _timeLimitSec;          // 服务器下发的每日试用秒数（null=无限/付费）
  int?               _trialStartMs;          // 今日首次连接成功的时间戳(ms)
  int                _adBonusSec = 0;        // 今日通过看广告累加的额外秒数
  String             _trialDay   = '';       // 计量所属 UTC 日期
  bool               _trialExceeded = false; // 今日试用是否已用尽
  Timer?             _trialTimer;

  VpnStatus     get status       => _status;
  ServerConfig? get activeServer => _activeServer;
  int?          get elapsedSecs  => _elapsedSecs;
  String?       get error        => _error;
  VpnProtocol   get protocol     => _protocol;
  bool          get isRelayMode  => _protocol != VpnProtocol.direct;
  RoutingMode   get routingMode  => _routingMode;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy      => _status == VpnStatus.connecting ||
                          _status == VpnStatus.disconnecting;

  // ── 本地用量/试用对外接口 ────────────────────────────────────
  int   get dailyUsed     => _dailyUsed;
  int?  get quotaBytes    => _quotaBytes;

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
  // 网络适配器对外显示的描述（Windows ipconfig / 网络连接里可见）。
  // 中文环境显示「MirrorSpeed 加速隧道」，其它语言显示「MirrorSpeed VPN」，
  // 绝不暴露 WireGuard 字样。
  static String _adapterDescription() {
    final locale = Platform.localeName.toLowerCase(); // e.g. zh_cn / en_us
    return locale.startsWith('zh') ? 'MirrorSpeed 加速隧道' : 'MirrorSpeed VPN';
  }

  Future<void> initialize() async {
    await AmneziaWG.instance.initialize(
      interfaceName: 'mirrorspeed',
      description:    _adapterDescription(),
    );
    _stageSub = AmneziaWG.instance.vpnStageSnapshot.listen(_onStage);
    await _loadUsage();
    await _loadTrial();

    // 恢复上次选择的路由模式
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('routing_mode');
    if (saved == RoutingMode.smart.name) {
      _routingMode = RoutingMode.smart;
      notifyListeners();
    }

    // 冷启动采纳已在运行的隧道（返回键退后台后进程被系统回收又重开的情况）：
    // 直接显示「已连接」，避免用户再点连接而叠加第二条隧道；试用沿用已持久化
    // 的开始时间继续倒计时（不会重置回 30 分钟）。
    await _adoptRunningTunnel();
  }

  Future<void> _adoptRunningTunnel() async {
    try {
      final st = await AmneziaWG.instance.stage();
      if (st == VpnStage.connected && _status != VpnStatus.connected) {
        _status        = VpnStatus.connected;
        _statsBaseline = null;
        _startUsagePolling();
        _startTrialTracking();   // 复用已持久化 _trialStartMs，墙钟继续
        notifyListeners();
      }
    } catch (_) {}
  }

  /// 配置加载后把 activeServer 绑回上次连接的节点（冷启动采纳隧道时用）。
  Future<void> bindActiveServer(List<ServerConfig> servers) async {
    if (_activeServer != null || servers.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('last_server_id');
    if (id == null) return;
    final match = servers.where((s) => s.id == id);
    if (match.isNotEmpty) { _activeServer = match.first; notifyListeners(); }
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

      await AmneziaWG.instance.startVpn(
        serverAddress:            '${server.endpoint}:$effectivePort',
        wgQuickConfig:            wgConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 直连兜底：到时仍未确认连通 → 切换 wstunnel 443 中继（层 2）。
      // 16s 给 _postConnectCheck 的多次探测（约 4+5+1+5s）留足时间，避免
      // 在直连其实可用、只是数据面稍慢稳定时被过早切走。
      // 使用 relayHost（域名）而非 endpoint（可能为 IP），确保 TLS 证书匹配。
      _fallbackTimer = Timer(
        const Duration(seconds: 16),
        () => _switchToRelay(server, relayBaseUrl: 'wss://${server.relayHost}'),
      );

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
        try { await AmneziaWG.instance.stopVpn(); } catch (_) {}
        _error  = e.message ?? e.toString();
        _status = VpnStatus.error;
      }
      notifyListeners();
    } catch (e) {
      try { await AmneziaWG.instance.stopVpn(); } catch (_) {}
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
    try { await AmneziaWG.instance.stopVpn(); } catch (_) {}
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

      await AmneziaWG.instance.startVpn(
        serverAddress:            '127.0.0.1:$localPort',
        wgQuickConfig:            relayConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 等 20 秒确认连通；超时则尝试下一层
      _fallbackTimer = Timer(const Duration(seconds: 20), () async {
        if (_status != VpnStatus.connected) {
          await _relay.stop();
          final cfUrl = server.cfRelayUrl;
          if (!isCf && cfUrl != null) {
            // 层 3：wstunnel-443 超时 → 尝试 Cloudflare Tunnel
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
    _sessionPort      = null;    // 主动断开后，下次连接重新基于时间计算端口
    _switchingToRelay = false;   // 确保 disconnected 事件不误判为中继切换中
    _status = VpnStatus.disconnecting;
    notifyListeners();
    // 关键：第一步就拆隧道（带超时，避免平台通道挂起导致永远断不开）。
    try {
      await AmneziaWG.instance.stopVpn()
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
        final st = await AmneziaWG.instance.stage();
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
        try { await AmneziaWG.instance.stopVpn(); } catch (_) {}
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
  Future<void> measureLatencies(List<ServerConfig> servers) async {
    await Future.wait(servers.map((s) async {
      try {
        final sw = Stopwatch()..start();
        await http.get(
          Uri.parse('https://${s.endpoint}/vpn-api/health'),
        ).timeout(const Duration(seconds: 5));
        sw.stop();
        s.latencyMs = sw.elapsedMilliseconds;
      } catch (_) {
        s.latencyMs = null;
      }
      notifyListeners();
    }));
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
    final total = await AmneziaWG.instance.transfer()
        .timeout(const Duration(seconds: 3), onTimeout: () => -1);
    _rollDayIfNeeded();
    if (total < 0) return;                 // 隧道未起 / 平台不支持
    if (_statsBaseline == null) { _statsBaseline = total; return; }
    var delta = total - _statsBaseline!;
    if (delta < 0) delta = total;          // 计数归零（隧道重启）
    _statsBaseline = total;
    if (delta <= 0) return;
    _dailyUsed += delta;
    _persistUsage();
    notifyListeners();
  }

  // ── 时间试用实现（#3）+ 看广告延长（#4）─────────────────────────
  Future<void> _loadTrial() async {
    final prefs = await SharedPreferences.getInstance();
    _trialDay     = prefs.getString('trial_day') ?? _utcDay();
    _trialStartMs = prefs.getInt('trial_start_ms');
    _adBonusSec   = prefs.getInt('trial_bonus_sec') ?? 0;
    _rollTrialDayIfNeeded();
    _recomputeTrial();
  }

  Future<void> _persistTrial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('trial_day', _trialDay);
    if (_trialStartMs == null) {
      await prefs.remove('trial_start_ms');
    } else {
      await prefs.setInt('trial_start_ms', _trialStartMs!);
    }
    await prefs.setInt('trial_bonus_sec', _adBonusSec);
  }

  void _rollTrialDayIfNeeded() {
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

  // 免费用户首次连接成功：启动倒计时（一旦开始按墙钟连续走，断开也不停）。
  void _startTrialTracking() {
    if (_timeLimitSec == null) return;          // 付费用户不计
    _rollTrialDayIfNeeded();
    _trialStartMs ??= DateTime.now().millisecondsSinceEpoch;
    _persistTrial();
    _trialTimer?.cancel();
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) => _recomputeTrial());
    _recomputeTrial();
  }

  // 计算剩余、刷新 UI、用尽则断开。
  void _recomputeTrial() {
    if (_timeLimitSec == null) { _trialExceeded = false; return; }
    _rollTrialDayIfNeeded();
    final exhausted = _trialStartMs != null && trialRemainingSec <= 0;
    if (exhausted && !_trialExceeded) {
      _trialExceeded = true;
      if (isConnected || _status == VpnStatus.connecting) {
        debugPrint('[VPN] 今日免费试用时长已用尽，断开连接');
        disconnect();
      }
    }
    notifyListeners();
  }

  /// 看完一条激励视频 → 增加奖励时长（#4）。立即生效，可解除「已用尽」。
  Future<void> addAdBonusMinutes(int minutes) async {
    _rollTrialDayIfNeeded();
    _adBonusSec += minutes * 60;
    await _persistTrial();
    if (trialRemainingSec > 0) _trialExceeded = false;
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
    _stageSub?.cancel();
    _timer?.cancel();
    // 注意：销毁时【不】拆隧道。返回键/切后台/被系统回收都应保持 VPN 运行，
    // 下次打开自动采纳；仅右上角「退出」键通过 disconnect() 主动断开。
    super.dispose();
  }
}
