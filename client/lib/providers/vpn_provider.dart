import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // PlatformException
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import '../models/server_config.dart';
import '../services/ws_relay_service.dart';
import '../env.dart';

enum VpnStatus   { disconnected, connecting, connected, disconnecting, error }
enum VpnProtocol { direct, relay }

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
  final WsRelayService _relay          = WsRelayService();

  VpnStatus     get status       => _status;
  ServerConfig? get activeServer => _activeServer;
  int?          get elapsedSecs  => _elapsedSecs;
  String?       get error        => _error;
  VpnProtocol   get protocol     => _protocol;
  bool          get isRelayMode  => _protocol == VpnProtocol.relay;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy      => _status == VpnStatus.connecting ||
                          _status == VpnStatus.disconnecting;

  // ── 初始化（app 启动时调用一次）────────────────────────────
  Future<void> initialize() async {
    await WireGuardFlutter.instance.initialize(interfaceName: 'wg0');
    _stageSub = WireGuardFlutter.instance.vpnStageSnapshot.listen(_onStage);
  }

  void _onStage(VpnStage stage) {
    switch (stage) {
      case VpnStage.connected:
        _fallbackTimer?.cancel(); // 握手成功，取消回退计时器
        _status = VpnStatus.connected;
        _startTimer();
      case VpnStage.connecting:
        _status = VpnStatus.connecting;
      case VpnStage.disconnected:
        _status = VpnStatus.disconnected;
        _stopTimer();
        // 中继切换过程中不清除 activeServer
        if (!_switchingToRelay && _activeServer != null && _error == null) {
          _activeServer = null;
        }
        _switchingToRelay = false;
      case VpnStage.disconnecting:
        _status = VpnStatus.disconnecting;
      default:
        break;
    }
    notifyListeners();
  }

  // ── 连接（直连 WireGuard，12 秒超时后自动回退到 WebSocket 中继）──
  Future<void> connect(ServerConfig server) async {
    _error            = null;
    _status           = VpnStatus.connecting;
    _activeServer     = server;
    _protocol         = VpnProtocol.direct;
    _switchingToRelay = false;
    _fallbackTimer?.cancel();
    notifyListeners();

    try {
      await WireGuardFlutter.instance.startVpn(
        serverAddress:            '${server.endpoint}:${server.port}',
        wgQuickConfig:            server.wgConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 12 秒内未收到 connected 事件 → 自动切换中继
      _fallbackTimer = Timer(
        const Duration(seconds: 12),
        () => _switchToRelay(server),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_server_id', server.id);
    } on PlatformException catch (e) {
      if (e.code == 'Permissions are not given' ||
          (e.message ?? '').contains('Permissions are not given')) {
        _error  = '请在刚才弹出的对话框中允许 VPN，然后重新点击连接';
        _status = VpnStatus.disconnected;
      } else {
        _error  = e.message ?? e.toString();
        _status = VpnStatus.error;
      }
      notifyListeners();
    } catch (e) {
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  // ── WebSocket 中继回退 ───────────────────────────────────────
  Future<void> _switchToRelay(ServerConfig server) async {
    if (_status == VpnStatus.connected) return; // 已直连成功，无需切换

    debugPrint('[VPN] 直连 12 秒超时，切换 WebSocket 中继...');
    _switchingToRelay = true;
    _protocol         = VpnProtocol.relay;
    _status           = VpnStatus.connecting;
    _error            = null;
    notifyListeners();

    // 停止正在进行的直连尝试
    try { await WireGuardFlutter.instance.stopVpn(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));

    // wstunnel WebSocket 路径：/udp/127.0.0.1/<WG端口>
    // Nginx /secure-tunnel/ 代理 → wstunnel:2080 → WireGuard UDP
    final wsUrl = 'wss://${server.endpoint}/secure-tunnel/'
                  'udp/127.0.0.1/${server.port}';

    // 解析服务器 IP，用于在 AllowedIPs 中排除（防止 WebSocket 中继回环）
    // 此时 VPN 未启动，DNS 走物理网卡，域名本身不被封所以能正常解析
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
      final localPort = await _relay.start(wsUrl);
      final relayConf = _buildRelayConf(server.wgConf, localPort, serverIp);

      await WireGuardFlutter.instance.startVpn(
        serverAddress:            '127.0.0.1:$localPort',
        wgQuickConfig:            relayConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 中继模式额外等 20 秒
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(seconds: 20), () async {
        if (_status != VpnStatus.connected) {
          await _relay.stop();
          _error  = '无法连接到 VPN（直连与中继均失败，请检查网络）';
          _status = VpnStatus.error;
          notifyListeners();
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
  String _buildRelayConf(String wgConf, int relayPort, String? serverIp) {
    // 1. Endpoint 改为本地中继端口
    var conf = wgConf.replaceAll(
      RegExp(r'Endpoint\s*=\s*\S+'),
      'Endpoint     = 127.0.0.1:$relayPort',
    );

    // 2. AllowedIPs
    String allowedIps;
    if (serverIp != null) {
      // 全隧道：覆盖 0.0.0.0/0，但排除服务器 IP（防 WebSocket 回环）
      allowedIps = _ipv4AllExcept(serverIp).join(', ');
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

  /// 替换或插入 WireGuard 配置中的 DNS 行
  String _setDns(String conf, String dnsServers) {
    final line = 'DNS          = $dnsServers';
    if (conf.contains(RegExp(r'^\s*DNS\s*=', multiLine: true))) {
      return conf.replaceAll(
          RegExp(r'^\s*DNS\s*=\s*[^\n]+', multiLine: true), line);
    }
    return conf.replaceFirst(RegExp(r'\[Peer\]'), '$line\n\n[Peer]');
  }

  /// 计算覆盖整个 IPv4 地址空间但排除指定 /32 的 CIDR 列表（共 32 条）。
  ///
  /// 原理：沿二叉树从根（0.0.0.0/0）走到目标叶子（excludeIp/32），
  /// 在每一层收集"另一半"子树，这些子树的并集 = 全空间 − excludeIp/32。
  List<String> _ipv4AllExcept(String excludeIp) {
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

  String _intToIp(int n) =>
      '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';

  // ── 断开 ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _fallbackTimer?.cancel();
    _status = VpnStatus.disconnecting;
    notifyListeners();
    try {
      await WireGuardFlutter.instance.stopVpn();
      await _relay.stop();
      _protocol = VpnProtocol.direct;
    } catch (e) {
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
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

  // ── 延迟测量（HTTP HEAD 计时，无需 ICMP 权限）──────────────
  Future<void> measureLatencies(List<ServerConfig> servers) async {
    await Future.wait(servers.map((s) async {
      try {
        final sw = Stopwatch()..start();
        await http.head(
          Uri.parse('$kApiBase/api/releases/latest'),
        ).timeout(const Duration(seconds: 3));
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

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _stageSub?.cancel();
    _timer?.cancel();
    _relay.stop();
    super.dispose();
  }
}
