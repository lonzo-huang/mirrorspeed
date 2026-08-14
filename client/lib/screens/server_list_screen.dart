import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_service.dart';
import '../brand.dart';
import '../theme.dart';
import 'shared_nodes_screen.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});
  @override State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth    = context.read<AuthProvider>();
      final servers = auth.displayServers;
      context.read<VpnProvider>().measureLatencies(servers);
      // 列表打开即后台批量预热：在所有节点上提前建好 peer，点哪个都即时连。
      if (auth.isLoggedIn) {
        ApiService.instance.ensurePeer();   // serverIds 省略 = 全部活跃节点
      }
    });
    // 延迟每 30 秒自动刷新一次（顶部仍保留手动刷新按钮）。
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final servers = context.read<AuthProvider>().displayServers;
      context.read<VpnProvider>().measureLatencies(servers, rounds: 1);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // 分组：先按大洲排序，再按国家聚拢（同国相邻），同国内按校正延迟升序。
  // 返回扁平的「行」列表：大洲表头 + 节点。
  List<_Row> _buildRows(List<ServerConfig> servers) {
    final sorted = [...servers]..sort((a, b) {
      final ca = kContinentOrder[a.continent] ?? 99;
      final cb = kContinentOrder[b.continent] ?? 99;
      if (ca != cb) return ca.compareTo(cb);
      final co = a.isoCountry.compareTo(b.isoCountry);   // 同洲内同国聚拢
      if (co != 0) return co;
      final la = a.displayLatencyMs ?? 9999;
      final lb = b.displayLatencyMs ?? 9999;
      return la.compareTo(lb);
    });
    final rows = <_Row>[];
    String? curCont;
    for (final s in sorted) {
      if (s.continent != curCont) {
        curCont = s.continent;
        rows.add(_Row.header(curCont));
      }
      rows.add(_Row.server(s));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final vpn     = context.watch<VpnProvider>();
    final servers = auth.displayServers;
    final rows    = _buildRows(servers);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('服务器','Servers'), style: const TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: tr('刷新延迟','Refresh latency'),
            onPressed: () => vpn.measureLatencies(servers),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              _TierChip(label: tr('优质节点','Premium'), selected: true, onTap: () {}),
              const SizedBox(width: 8),
              _TierChip(
                label: tr('共享节点·免费','Shared·Free'), selected: false,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SharedNodesScreen())),
              ),
            ]),
          ),
        ),
      ),
      body: servers.isEmpty
          ? Center(child: Text(tr('暂无可用节点','No nodes available'), style: const TextStyle(color: Colors.white54)))
          : ListView.separated(
              // 底部留白避开悬浮底部导航栏（extendBody），否则最后几项被遮住、滚不到底。
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              // +1：列表首项为「智能选择」
              itemCount: rows.length + 1,
              separatorBuilder: (_, i) {
                // 表头前后留多一点空隙
                if (i + 1 <= rows.length && rows[i].isHeader) return const SizedBox(height: 14);
                return const SizedBox(height: 8);
              },
              itemBuilder: (ctx, i) {
                // 免费时长已用尽且当前未连接：禁止连接任何节点，给出提示。
                bool blockedByQuota() {
                  if (vpn.quotaExceeded && !vpn.isConnected) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(tr('免费时长已用完，看广告或升级后再连接',
                          'Free time used up — watch an ad or upgrade to connect')),
                      backgroundColor: kDanger,
                      duration: const Duration(seconds: 2),
                    ));
                    return true;
                  }
                  return false;
                }

                if (i == 0) {
                  return _AutoTile(
                    isActive: vpn.autoSelect && vpn.activeServer != null,
                    onTap: () async {
                      if (!auth.isLoggedIn) { context.go('/login'); return; }
                      if (blockedByQuota()) return;
                      context.go('/home');   // 切回主页查看连接状态
                      await vpn.connectAuto(servers);
                    },
                  );
                }
                final row = rows[i - 1];
                if (row.isHeader) {
                  return _ContinentHeader(code: row.continent!);
                }
                final server = row.server!;
                return _ServerTile(
                  server:   server,
                  isActive: !vpn.autoSelect && vpn.activeServer?.id == server.id,
                  onTap: () async {
                    // 未登录或仅展示节点：连接前先登录（#1）
                    if (!auth.isLoggedIn || server.isDisplayOnly) {
                      context.go('/login');
                      return;
                    }
                    if (blockedByQuota()) return;
                    context.go('/home');   // 切回主页查看连接状态
                    await vpn.setAutoSelect(false);   // 手动选择
                    if (vpn.isConnected) {
                      await vpn.switchServer(server);
                    } else {
                      await vpn.connect(server);
                    }
                  },
                );
              },
            ),
    );
  }
}

// ── 列表行：大洲表头 或 节点 ─────────────────────────────────────────
class _Row {
  final String? continent;     // 非 null → 表头
  final ServerConfig? server;  // 非 null → 节点
  _Row.header(this.continent) : server = null;
  _Row.server(this.server) : continent = null;
  bool get isHeader => continent != null;
}

class _ContinentHeader extends StatelessWidget {
  final String code;
  const _ContinentHeader({required this.code});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2, top: 2),
      child: Text(
        continentLabel(code, Brand.isZh).toUpperCase(),
        style: TextStyle(
          fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700,
          color: Colors.white.withOpacity(0.45)),
      ),
    );
  }
}

// ── 三档负载色块通用工具 ─────────────────────────────────────────────
// tier: 0 空闲(绿) · 1 适中(黄) · 2 繁忙(红)
Color _loadColor(int tier) =>
    tier == 0 ? kSuccess : (tier == 1 ? Colors.amber : kDanger);
String _loadLabel(int tier) => tier == 0
    ? tr('空闲','Idle')
    : (tier == 1 ? tr('适中','Busy') : tr('繁忙','Full'));

// 信号格颜色：4 满格绿 · 3 浅绿 · 2 黄 · 1 红 · 0 灰
Color _signalColor(int bars) {
  switch (bars) {
    case 4: return kSuccess;
    case 3: return Colors.lightGreen;
    case 2: return Colors.amber;
    case 1: return kDanger;
    default: return Colors.white24;
  }
}

// ── 信号格（4 格，高度递增）────────────────────────────────────────
/// 优质/共享 分区切换胶囊。
class _TierChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _TierChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? kBrand.withOpacity(0.18) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kBrand : Colors.white.withOpacity(0.12)),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? kBrand : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int bars;   // 0–4
  const _SignalBars({required this.bars});
  @override
  Widget build(BuildContext context) {
    final color = _signalColor(bars);
    const heights = [6.0, 9.0, 12.0, 15.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 4; i++) ...[
          Container(
            width: 3.5,
            height: heights[i],
            decoration: BoxDecoration(
              color: (i < bars) ? color : Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          if (i < 3) const SizedBox(width: 2),
        ],
      ],
    );
  }
}

// ── 智能选择项 ──────────────────────────────────────────────────────
class _AutoTile extends StatelessWidget {
  final bool         isActive;
  final VoidCallback onTap;
  const _AutoTile({ required this.isActive, required this.onTap });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? kBrand.withOpacity(0.18) : kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: kBrand, size: 26),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('智能选择','Auto select'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(tr('自动接入延迟最低、最空闲的节点','Picks the fastest, least busy node'),
                style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
            ])),
            if (isActive)
              const Icon(Icons.check_circle_rounded, color: kBrand, size: 20)
            else
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
          ]),
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final ServerConfig server;
  final bool          isActive;
  final VoidCallback  onTap;
  const _ServerTile({ required this.server, required this.isActive, required this.onTap });

  @override
  Widget build(BuildContext context) {
    final dispLat = server.displayLatencyMs;   // 校正后展示延迟（仅用于判断是否超时）
    final bars    = server.signalBars;
    final tier    = server.loadTier;
    // 状态显示：以服务器上报的 status 为权威。
    //   offline           → 「离线」
    //   仍在测量           → 转圈
    //   探测失败但非离线    → 不显示「超时」（如西班牙节点健康检查域名问题导致客户端探测
    //                        失败，但服务端 status 仍在线），按在线展示信号格
    //   正常               → 按校正延迟显示信号格
    final Widget statusW;
    if (server.status == 'offline') {
      statusW = Text(tr('离线', 'offline'),
          style: const TextStyle(color: kDanger, fontSize: 13, fontWeight: FontWeight.w600));
    } else if (!server.latencyMeasured) {
      statusW = SizedBox(width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withOpacity(0.3)));
    } else if (dispLat == null) {
      statusW = _SignalBars(bars: server.status == 'degraded' ? 2 : 3);
    } else {
      statusW = _SignalBars(bars: bars);
    }
    return Material(
      color: isActive ? kBrand.withOpacity(0.18) : kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Text(server.flagEmoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.displayLabel(Brand.isZh),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 3),
              Row(children: [
                // 三档负载色块
                Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: _loadColor(tier), borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 5),
                Text(_loadLabel(tier),
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
              ]),
            ])),
            // 状态指示（信号格 / 离线 / 测量中），逻辑见上方 statusW。
            statusW,
            const SizedBox(width: 12),
            if (isActive)
              const Icon(Icons.check_circle_rounded, color: kBrand, size: 20)
            else
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
          ]),
        ),
      ),
    );
  }
}
