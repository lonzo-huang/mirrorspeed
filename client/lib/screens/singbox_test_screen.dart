import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  // 测速：fingerprint → 延迟 ms（-1=不可达，缺省=未测）
  final Map<String, int> _latency = {};
  bool _testing = false;
  int _tested = 0;

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
        case 'connected':
          setState(() => _stage = VpnStage.connected);
          _probeEgress();   // 连上后自动验证出口是否真的通
          break;
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

  /// TCP 连通测速：并发连 server:port，拿握手延迟。仅验证服务器在线+可达，
  /// 不代表走代理能翻墙（那需 sing-box urltest）。测完按延迟排序、死的沉底。
  Future<void> _testAll() async {
    if (_nodes.isEmpty || _testing) return;
    setState(() { _testing = true; _tested = 0; _latency.clear(); });
    const concurrency = 40;
    for (var i = 0; i < _nodes.length; i += concurrency) {
      final batch = _nodes.skip(i).take(concurrency);
      await Future.wait(batch.map((n) async {
        final ms = await _ping(n);
        if (!mounted) return;
        setState(() { _latency[n.fingerprint] = ms; _tested++; });
      }));
      if (!mounted) return;
    }
    // 排序：可达按 ms 升序，不可达沉底
    setState(() {
      _nodes.sort((a, b) {
        final la = _latency[a.fingerprint] ?? 999999;
        final lb = _latency[b.fingerprint] ?? 999999;
        final va = la < 0 ? 100000 : la;
        final vb = lb < 0 ? 100000 : lb;
        return va.compareTo(vb);
      });
      _testing = false;
    });
    final alive = _latency.values.where((v) => v >= 0).length;
    _add('测速完成：$alive/${_nodes.length} 可达');
  }

  /// 连上后通过隧道验证出口：请 generate_204（应 204）+ 查出口 IP。
  /// 这才是"节点真能翻墙"的证据；失败原因(DNS/连接/超时)直接打日志。
  Future<void> _probeEgress() async {
    _add('隧道已建立，验证出口…（等路由生效）');
    await Future.delayed(const Duration(milliseconds: 1500));
    // 1) 纯 IP 探测（不经 DNS）：只测代理握手/转发是否通
    final ipOk = await _probe('https://1.1.1.1/cdn-cgi/trace', '纯IP(1.1.1.1)');
    // 2) 域名探测：测 DNS + 代理
    final domainOk = await _probe('https://www.gstatic.com/generate_204', '域名(gstatic)');

    if (ipOk && domainOk) {
      _add('结论：✅ 此节点可正常翻墙');
    } else if (ipOk && !domainOk) {
      _add('结论：⚠️ 代理通但 DNS 解析不通（DNS 配置问题，非节点问题）');
    } else {
      _add('结论：❌ 代理握手/转发失败（此节点不可用或协议参数不对）');
    }
  }

  /// 返回是否连通。[label] 仅用于日志。
  Future<bool> _probe(String url, String label) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final sw = Stopwatch()..start();
      final req = await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      sw.stop();
      await res.drain();
      final ok = res.statusCode == 200 || res.statusCode == 204;
      _add('${ok ? "✅" : "⚠️"} $label → HTTP ${res.statusCode} (${sw.elapsedMilliseconds}ms)');
      return ok;
    } catch (e) {
      _add('❌ $label → $e');
      return false;
    } finally {
      c.close(force: true);
    }
  }

  Future<int> _ping(FreeNode n) async {
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      s = await Socket.connect(n.server, n.port,
          timeout: const Duration(seconds: 3));
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      s?.destroy();
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

  Widget _latencyBadge(int? ms) {
    if (ms == null) return const Text('—', style: TextStyle(color: Colors.grey, fontSize: 12));
    if (ms < 0) return const Text('超时', style: TextStyle(color: Colors.red, fontSize: 12));
    final color = ms < 300 ? Colors.green : (ms < 800 ? Colors.orange : Colors.red);
    return Text('$ms ms', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600));
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
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _testing || _nodes.isEmpty ? null : _testAll,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.speed),
                  label: Text(_testing ? '测速中 $_tested/${_nodes.length}' : '测速全部'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || _selected == null ? null : _connect,
                  icon: const Icon(Icons.vpn_lock),
                  label: const Text('连接'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy ? null : _disconnect,
                child: const Text('断开'),
              ),
            ]),
            const SizedBox(height: 8),
            // 节点列表（测速后按延迟排序、死的置灰）
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.builder(
                  itemCount: _nodes.length,
                  itemBuilder: (_, i) {
                    final n = _nodes[i];
                    final ms = _latency[n.fingerprint];
                    final dead = ms != null && ms < 0;
                    final selected = identical(n, _selected);
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: Colors.blue.withOpacity(0.12),
                      enabled: !dead,
                      title: Text('${n.name}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: dead ? Colors.grey : null)),
                      subtitle: Text('${n.protocol} · ${n.server}:${n.port}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                      trailing: _latencyBadge(ms),
                      onTap: () => setState(() => _selected = n),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('日志', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.black.withOpacity(0.04),
                child: ListView.builder(
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(_log[i], style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
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
