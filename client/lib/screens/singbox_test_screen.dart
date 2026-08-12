import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/free_node.dart';
import '../services/free_node_service.dart';
import '../vpn/proxy_core_engine.dart';
import '../vpn/singbox_config.dart';
import '../vpn/vpn_engine.dart';

/// 临时测试页：验证 sing-box(共享节点)原生链路是否能真正连通。
/// 拉订阅 → 选一个节点 → 建 config → ProxyCoreEngine.start → 看状态。
/// 验证通过后本页会被正式的"共享节点"UI 取代。
class SingboxTestScreen extends StatefulWidget {
  const SingboxTestScreen({super.key});
  @override
  State<SingboxTestScreen> createState() => _SingboxTestScreenState();
}

class _SingboxTestScreenState extends State<SingboxTestScreen> {
  final _engine = ProxyCoreEngine();
  final _log = <String>[];
  List<FreeNode> _nodes = [];
  FreeNode? _selected;
  VpnStage _stage = VpnStage.disconnected;
  StreamSubscription? _rawSub;
  bool _busy = false;

  // 直接订阅原生原始事件流（含 "error: ..." 报错细节）。
  static const EventChannel _rawStage = EventChannel('mirrorspeed/singbox/stage');

  @override
  void initState() {
    super.initState();
    _rawSub = _rawStage.receiveBroadcastStream().listen((e) {
      final s = '$e';
      _add('◆ $s');
      switch (s) {
        case 'connecting':    setState(() => _stage = VpnStage.connecting); break;
        case 'connected':     setState(() => _stage = VpnStage.connected); break;
        case 'disconnecting': setState(() => _stage = VpnStage.disconnecting); break;
        case 'disconnected':  setState(() => _stage = VpnStage.disconnected); break;
      }
    });
    _loadNodes();
  }

  @override
  void dispose() {
    _rawSub?.cancel();
    super.dispose();
  }

  void _add(String m) {
    setState(() => _log.insert(0, '${DateTime.now().toString().substring(11, 19)}  $m'));
  }

  Future<void> _loadNodes() async {
    setState(() => _busy = true);
    try {
      _add('拉取订阅…');
      for (final line in await FreeNodeService.instance.diagnose(top: true)) {
        _add(line);
      }
      final nodes = await FreeNodeService.instance.fetch(top: true);
      setState(() {
        _nodes = nodes;
        _selected = nodes.isNotEmpty ? nodes.first : null;
      });
      _add('拿到 ${nodes.length} 个节点');
    } catch (e) {
      _add('拉订阅失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final node = _selected;
    if (node == null) return;
    setState(() => _busy = true);
    try {
      _add('连接 ${node.name} (${node.protocol} ${node.server}:${node.port})');
      final cfg = SingboxConfig.build(node, smart: false);
      await _engine.start(EngineStartParams(singboxConfig: cfg));
      _add('start 已下发(等系统 VPN 授权 & 隧道建立)');
    } catch (e) {
      _add('连接失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _engine.stop();
      _add('stop 已下发');
    } catch (e) {
      _add('断开失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('sing-box 测试')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('状态: ${_stage.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: _busy ? null : _loadNodes, icon: const Icon(Icons.refresh)),
            ]),
            const SizedBox(height: 8),
            DropdownButton<FreeNode>(
              isExpanded: true,
              value: _selected,
              hint: const Text('选择节点'),
              items: _nodes
                  .map((n) => DropdownMenuItem(
                        value: n,
                        child: Text('${n.name}  ·  ${n.protocol}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (n) => setState(() => _selected = n),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || _selected == null ? null : _connect,
                  icon: const Icon(Icons.vpn_lock),
                  label: const Text('连接'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _disconnect,
                  icon: const Icon(Icons.stop),
                  label: const Text('断开'),
                ),
              ),
            ]),
            const Divider(height: 24),
            const Text('日志', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                color: Colors.black.withOpacity(0.04),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(_log[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
