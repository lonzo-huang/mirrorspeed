import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/free_node.dart';
import '../services/free_node_service.dart';
import '../vpn/proxy_core_engine.dart';
import '../vpn/singbox_config.dart';
import '../vpn/vpn_engine.dart';

/// 「共享节点」(免费机场，走 sing-box)状态管理，与 WireGuard 的 [VpnProvider] 平行。
/// 两条隧道系统级互斥：连接共享节点前先停 WireGuard（[onNeedStopOther]）。
class SharedNodeProvider extends ChangeNotifier {
  final ProxyCoreEngine _engine = ProxyCoreEngine();

  /// 连接前需要停掉的另一条隧道（WireGuard）。由 app 层注入。
  Future<void> Function()? onNeedStopOther;

  List<FreeNode> _nodes = [];
  final Map<String, int> _latency = {};   // fingerprint → ms（-1=不可达）
  FreeNode? _active;
  VpnStage  _stage = VpnStage.disconnected;
  bool      _loading = false;
  bool      _testing = false;
  int       _tested = 0;
  String?   _error;

  List<FreeNode> get nodes => _nodes;
  FreeNode?      get active => _active;
  VpnStage       get stage => _stage;
  bool           get loading => _loading;
  bool           get testing => _testing;
  int            get tested => _tested;
  String?        get error => _error;
  bool get isConnected  => _stage == VpnStage.connected;
  bool get isConnecting => _stage == VpnStage.connecting;
  int? latencyOf(FreeNode n) => _latency[n.fingerprint];

  StreamSubscription? _stageSub;

  SharedNodeProvider() {
    _stageSub = _engine.stageStream.listen((s) {
      _stage = s;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    super.dispose();
  }

  /// 拉取精选清单（clash_top50.yaml）。
  Future<void> load() async {
    _loading = true; _error = null; notifyListeners();
    try {
      _nodes = await FreeNodeService.instance.fetch(top: true);
      if (_nodes.isEmpty) _error = '未获取到节点';
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false; notifyListeners();
    }
  }

  /// 并发 TCP 测速（仅测服务器可达性，非代理可用性）；按延迟排序、不可达沉底。
  Future<void> testAll() async {
    if (_nodes.isEmpty || _testing) return;
    _testing = true; _tested = 0; _latency.clear(); notifyListeners();
    const conc = 40;
    for (var i = 0; i < _nodes.length; i += conc) {
      await Future.wait(_nodes.skip(i).take(conc).map((n) async {
        _latency[n.fingerprint] = await _ping(n);
        _tested++;
      }));
      notifyListeners();
    }
    _nodes.sort((a, b) {
      final la = _latency[a.fingerprint] ?? 999999;
      final lb = _latency[b.fingerprint] ?? 999999;
      return (la < 0 ? 100000 : la).compareTo(lb < 0 ? 100000 : lb);
    });
    _testing = false; notifyListeners();
  }

  Future<int> _ping(FreeNode n) async {
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      s = await Socket.connect(n.server, n.port, timeout: const Duration(seconds: 3));
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      s?.destroy();
    }
  }

  /// 连接某个共享节点。先停 WireGuard（系统级只允许一条隧道）。
  Future<void> connect(FreeNode node) async {
    _error = null;
    try {
      await onNeedStopOther?.call();
    } catch (_) {}
    _active = node;
    notifyListeners();
    try {
      final cfg = SingboxConfig.build(node, smart: false);
      await _engine.start(EngineStartParams(singboxConfig: cfg));
    } catch (e) {
      _error = '$e';
      _active = null;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      await _engine.stop();
    } catch (_) {}
    // "disconnected" 事件现在由原生 onDestroy 发出 = sing-box 的 VpnService 已被系统
    // 完全销毁、VPN 已释放。必须等到这个信号再返回（VpnProvider.connect 据此才启动
    // WireGuard），否则 WG 会和系统的 VPN 拆除回调在主线程撞车 → App 被强杀。
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (_stage != VpnStage.disconnected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _active = null;
    notifyListeners();
  }
}
