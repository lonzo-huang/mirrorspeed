import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import '../models/server_config.dart';
import '../env.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

class VpnProvider extends ChangeNotifier {
  VpnStatus    _status        = VpnStatus.disconnected;
  ServerConfig? _activeServer;
  int?          _elapsedSecs;
  String?       _error;
  Timer?        _timer;
  StreamSubscription<VpnStage>? _stageSub;

  VpnStatus     get status       => _status;
  ServerConfig? get activeServer => _activeServer;
  int?          get elapsedSecs  => _elapsedSecs;
  String?       get error        => _error;

  bool get isConnected    => _status == VpnStatus.connected;
  bool get isBusy         => _status == VpnStatus.connecting ||
                             _status == VpnStatus.disconnecting;

  // ── 初始化（app 启动时调用一次）────────────────────────────
  Future<void> initialize() async {
    await WireGuardFlutter.instance.initialize(interfaceName: 'wg0');
    _stageSub = WireGuardFlutter.instance.vpnStageSnapshot.listen(_onStage);
  }

  void _onStage(VpnStage stage) {
    switch (stage) {
      case VpnStage.connected:
        _status = VpnStatus.connected;
        _startTimer();
      case VpnStage.connecting:
        _status = VpnStatus.connecting;
      case VpnStage.disconnected:
        _status = VpnStatus.disconnected;
        _stopTimer();
        if (_activeServer != null && _error == null) _activeServer = null;
      case VpnStage.disconnecting:
        _status = VpnStatus.disconnecting;
      default:
        break;
    }
    notifyListeners();
  }

  // ── 连接 ────────────────────────────────────────────────────
  Future<void> connect(ServerConfig server) async {
    _error  = null;
    _status = VpnStatus.connecting;
    _activeServer = server;
    notifyListeners();

    try {
      await WireGuardFlutter.instance.startVpn(
        serverAddress:              '${server.endpoint}:${server.port}',
        wgQuickConfig:              server.wgConf,
        providerBundleIdentifier:   kProviderBundle, // iOS only
      );
      // 保存最后使用的节点
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_server_id', server.id);
    } catch (e) {
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  // ── 断开 ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _status = VpnStatus.disconnecting;
    notifyListeners();
    try {
      await WireGuardFlutter.instance.stopVpn();
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
        final sw  = Stopwatch()..start();
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
    final s = _elapsedSecs ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
