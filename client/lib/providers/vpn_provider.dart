import 'dart:async';
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
    try {
      final localPort = await _relay.start(wsUrl);
      final relayConf = _buildRelayConf(server.wgConf, localPort);

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

  /// 将直连配置改写为中继模式配置：
  ///   Endpoint   → 127.0.0.1:<relayPort>
  ///   AllowedIPs → VPN 子网（避免路由环路：Cloudflare 走物理网卡）
  ///   DNS        → 114.114.114.114, 223.5.5.5（国内可用）
  ///
  /// 为什么要替换 DNS：
  ///   中继模式下 AllowedIPs 仅含 VPN 子网，DNS 查询走物理网卡而非隧道。
  ///   1.1.1.1 / 8.8.8.8 在中国大陆被封锁，必须换为国内 DNS 否则无法解析。
  String _buildRelayConf(String wgConf, int relayPort) {
    // 1. Endpoint 改为本地中继端口
    var conf = wgConf.replaceAll(
      RegExp(r'Endpoint\s*=\s*\S+'),
      'Endpoint     = 127.0.0.1:$relayPort',
    );

    // 2. 从 Address 提取 VPN 子网（如 10.200.0.5/32 → 10.200.0.0/24）
    //    仅路由 VPN 子网：WebSocket 连接到 Cloudflare 走物理网卡，不循环
    final addrMatch = RegExp(r'Address\s*=\s*([\d.]+)/').firstMatch(conf);
    final vpnSubnet = addrMatch != null
        ? '${addrMatch.group(1)!.split('.').take(3).join('.')}.0/24'
        : '10.200.0.0/24';
    conf = conf.replaceAll(
      RegExp(r'AllowedIPs\s*=\s*[^\n]+'),
      'AllowedIPs   = $vpnSubnet',
    );

    // 3. 替换 DNS 为国内可用服务器
    //    114.114.114.114 = 电信 / 联通 / 移动三网通用
    //    223.5.5.5       = 阿里 AliDNS（备用）
    const chinaDns = 'DNS          = 114.114.114.114, 223.5.5.5';
    if (conf.contains(RegExp(r'^\s*DNS\s*=', multiLine: true))) {
      conf = conf.replaceAll(
        RegExp(r'^\s*DNS\s*=\s*[^\n]+', multiLine: true),
        chinaDns,
      );
    } else {
      // 原配置无 DNS 行时，插入到 [Interface] 段最后一行（[Peer] 前）
      conf = conf.replaceFirst(
        RegExp(r'(\[Peer\])'),
        '$chinaDns\n\n[Peer]',
      );
    }

    return conf;
  }

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
