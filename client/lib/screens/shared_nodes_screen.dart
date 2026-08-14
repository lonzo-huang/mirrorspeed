import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shared_node_provider.dart';

/// 「共享节点」页：免费机场节点(sing-box)。列表 + 测速 + 连接/断开。
/// 与 WireGuard「优质节点」互斥(连这个会自动断开那个)。
class SharedNodesScreen extends StatefulWidget {
  const SharedNodesScreen({super.key});
  @override
  State<SharedNodesScreen> createState() => _SharedNodesScreenState();
}

class _SharedNodesScreenState extends State<SharedNodesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<SharedNodeProvider>();
      if (p.nodes.isEmpty) p.load().then((_) => p.testAll());
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SharedNodeProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('共享节点（免费）'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: p.loading ? null : () => p.load().then((_) => p.testAll()),
          ),
        ],
      ),
      body: Column(
        children: [
          _statusBar(p),
          if (p.loading) const LinearProgressIndicator(),
          if (p.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('加载失败：${p.error}', style: const TextStyle(color: Colors.red)),
            ),
          Expanded(child: _list(p)),
        ],
      ),
    );
  }

  Widget _statusBar(SharedNodeProvider p) {
    final connected = p.isConnected;
    final connecting = p.isConnecting;
    final name = p.active?.name ?? '未连接';
    return Container(
      color: connected ? Colors.green.withOpacity(0.12) : Colors.grey.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(connected ? Icons.lock : Icons.lock_open,
              color: connected ? Colors.green : Colors.grey, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              connecting ? '连接中…' : (connected ? '已连接：$name' : '未连接'),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (connected || connecting)
            TextButton(
              onPressed: () => context.read<SharedNodeProvider>().disconnect(),
              child: const Text('断开'),
            ),
          if (!connected && !connecting)
            TextButton.icon(
              onPressed: p.testing || p.nodes.isEmpty ? null : () => p.testAll(),
              icon: p.testing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed, size: 18),
              label: Text(p.testing ? '${p.tested}/${p.nodes.length}' : '测速'),
            ),
        ],
      ),
    );
  }

  Widget _list(SharedNodeProvider p) {
    if (p.nodes.isEmpty && !p.loading) {
      return const Center(child: Text('暂无节点，下拉刷新'));
    }
    return ListView.separated(
      itemCount: p.nodes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final n = p.nodes[i];
        final ms = p.latencyOf(n);
        final dead = ms != null && ms < 0;
        final isActive = identical(n, p.active);
        return ListTile(
          dense: true,
          enabled: !dead,
          selected: isActive,
          leading: Icon(
            isActive && p.isConnected ? Icons.check_circle : Icons.public,
            color: isActive && p.isConnected ? Colors.green : (dead ? Colors.grey : null),
            size: 22,
          ),
          title: Text(_title(n), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: dead ? Colors.grey : null)),
          subtitle: Text('${n.protocol.toUpperCase()} · ${n.server}:${n.port}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: _latencyBadge(ms),
          onTap: dead ? null : () => context.read<SharedNodeProvider>().connect(n),
        );
      },
    );
  }

  // 节点名多为脏字符串（含 emoji 旗帜/流量/备注）。格式化成「旗帜 国家 · 序号」，
  // 从名字里抽出旗帜 emoji 推国家码；抽不到就用清理后的短名。
  String _title(node) {
    final name = node.name as String;
    final runes = name.runes.toList();
    // 找连续两个区域指示符（旗帜 emoji）
    const base = 0x1F1E6;
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i] - base, b = runes[i + 1] - base;
      if (a >= 0 && a <= 25 && b >= 0 && b <= 25) {
        final flag = String.fromCharCodes([runes[i], runes[i + 1]]);
        final iso = String.fromCharCode(65 + a) + String.fromCharCode(65 + b);
        return '$flag $iso';
      }
    }
    // 无旗帜：去掉常见噪声（速率/管道符），取前一段
    var s = name.replaceAll(RegExp(r'\d+(\.\d+)?\s*[KMG]B/s'), '').trim();
    s = s.split('|').first.split('·').first.trim();
    if (s.length > 22) s = '${s.substring(0, 22)}…';
    return s.isEmpty ? node.server as String : s;
  }

  Widget _latencyBadge(int? ms) {
    if (ms == null) return const SizedBox.shrink();
    if (ms < 0) return const Text('超时', style: TextStyle(color: Colors.red, fontSize: 12));
    final c = ms < 300 ? Colors.green : (ms < 800 ? Colors.orange : Colors.red);
    return Text('$ms ms', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600));
  }
}
