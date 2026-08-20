import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shared_node_provider.dart';
import '../brand.dart';

// 分组表头（旗帜 + 本地化国家名 + 数量）。
class _Header {
  final String flag, name;
  final int count;
  _Header(this.flag, this.name, this.count);
}

// 从节点名里的旗帜 emoji 抽 ISO 国家码；无旗帜返回 ''。
String _isoOf(String name) {
  final runes = name.runes.toList();
  const base = 0x1F1E6;
  for (var i = 0; i < runes.length - 1; i++) {
    final a = runes[i] - base, b = runes[i + 1] - base;
    if (a >= 0 && a <= 25 && b >= 0 && b <= 25) {
      return String.fromCharCode(65 + a) + String.fromCharCode(65 + b);
    }
  }
  return '';
}

String _countryFlag(String iso) {
  if (iso.length != 2) return '';
  const base = 0x1F1E6;
  return String.fromCharCodes([base + (iso.codeUnitAt(0) - 65), base + (iso.codeUnitAt(1) - 65)]);
}

// ISO → 本地化国家名（按语言）。未收录回退 ISO 码。
String _countryName(String iso, bool zh) {
  if (iso.isEmpty) return zh ? '其他' : 'Other';
  final n = _kCountryNames[iso];
  if (n == null) return iso;
  return zh ? n[0] : n[1];
}

const Map<String, List<String>> _kCountryNames = {
  'HK': ['香港', 'Hong Kong'], 'TW': ['台湾', 'Taiwan'], 'JP': ['日本', 'Japan'],
  'KR': ['韩国', 'South Korea'], 'SG': ['新加坡', 'Singapore'], 'US': ['美国', 'United States'],
  'CA': ['加拿大', 'Canada'], 'GB': ['英国', 'United Kingdom'], 'DE': ['德国', 'Germany'],
  'FR': ['法国', 'France'], 'NL': ['荷兰', 'Netherlands'], 'RU': ['俄罗斯', 'Russia'],
  'IN': ['印度', 'India'], 'AU': ['澳大利亚', 'Australia'], 'BR': ['巴西', 'Brazil'],
  'IT': ['意大利', 'Italy'], 'ES': ['西班牙', 'Spain'], 'SE': ['瑞典', 'Sweden'],
  'CH': ['瑞士', 'Switzerland'], 'PL': ['波兰', 'Poland'], 'FI': ['芬兰', 'Finland'],
  'NO': ['挪威', 'Norway'], 'IE': ['爱尔兰', 'Ireland'], 'AT': ['奥地利', 'Austria'],
  'TR': ['土耳其', 'Turkey'], 'UA': ['乌克兰', 'Ukraine'], 'CZ': ['捷克', 'Czechia'],
  'RO': ['罗马尼亚', 'Romania'], 'VN': ['越南', 'Vietnam'], 'TH': ['泰国', 'Thailand'],
  'MY': ['马来西亚', 'Malaysia'], 'ID': ['印尼', 'Indonesia'], 'PH': ['菲律宾', 'Philippines'],
  'AE': ['阿联酋', 'UAE'], 'IL': ['以色列', 'Israel'], 'ZA': ['南非', 'South Africa'],
  'MX': ['墨西哥', 'Mexico'], 'AR': ['阿根廷', 'Argentina'], 'CL': ['智利', 'Chile'],
  'KZ': ['哈萨克斯坦', 'Kazakhstan'], 'CO': ['哥伦比亚', 'Colombia'], 'CN': ['中国', 'China'],
  'MO': ['澳门', 'Macau'], 'PT': ['葡萄牙', 'Portugal'], 'GR': ['希腊', 'Greece'],
  'HU': ['匈牙利', 'Hungary'], 'BE': ['比利时', 'Belgium'], 'DK': ['丹麦', 'Denmark'],
};

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
    // 按国家分组（节点已按延迟排序，组内保持该顺序）。
    final groups = <String, List<dynamic>>{};
    for (final n in p.nodes) {
      groups.putIfAbsent(_isoOf(n.name as String), () => []).add(n);
    }
    final zh = Brand.isZh;
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == '') return 1;
        if (b == '') return -1;
        return _countryName(a, zh).compareTo(_countryName(b, zh));
      });
    final rows = <dynamic>[];
    for (final k in keys) {
      rows.add(_Header(_countryFlag(k), _countryName(k, zh), groups[k]!.length));
      rows.addAll(groups[k]!);
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        if (row is _Header) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(children: [
              Text(row.flag.isEmpty ? '🌐' : row.flag, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text(row.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${row.count}', style: TextStyle(fontSize: 11, color: Colors.grey.withOpacity(0.7))),
            ]),
          );
        }
        final n = row;
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
            size: 20,
          ),
          title: Text(_lineName(n.name as String, n.server as String),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: dead ? Colors.grey : null)),
          subtitle: Text(n.server as String,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          trailing: _latencyBadge(ms),
          onTap: dead ? null : () => context.read<SharedNodeProvider>().connect(n),
        );
      },
    );
  }

  // 单条线路的展示名：去掉旗帜/协议/速率噪声，取一段可读文字；空则回退 IP。
  String _lineName(String name, String server) {
    var s = name.replaceAll(RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), '');
    s = s.replaceAll(RegExp(r'\d+(\.\d+)?\s*[KMG]B/s'), '');
    s = s.split('|').first.split('·').first.trim();
    s = s.replaceAll(RegExp(r'^\W+'), '').trim();
    if (s.length > 24) s = '${s.substring(0, 24)}…';
    return s.isEmpty ? server : s;
  }

  Widget _latencyBadge(int? ms) {
    if (ms == null) return const SizedBox.shrink();
    if (ms < 0) return const Text('超时', style: TextStyle(color: Colors.red, fontSize: 12));
    final c = ms < 300 ? Colors.green : (ms < 800 ? Colors.orange : Colors.red);
    return Text('$ms ms', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600));
  }
}
