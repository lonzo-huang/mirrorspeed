import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_service.dart';
import '../providers/shared_node_provider.dart';
import '../models/free_node.dart';
import '../utils/free_country.dart';
import '../brand.dart';
import '../theme.dart';
import '../app.dart' show rootMessengerKey;
import '../widgets/ms_top_controls.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});
  @override State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  Timer? _refreshTimer;
  late String _tier;   // premium=优质(WireGuard) / shared=共享(sing-box)

  @override
  void initState() {
    super.initState();
    // 按当前偏好落到对应 tab：共享连着/偏好共享 → 直接进共享 tab，与主页当前节点卡一致。
    _tier = context.read<SharedNodeProvider>().preferShared ? 'shared' : 'premium';
    if (_tier == 'shared') {
      final p = context.read<SharedNodeProvider>();
      if (p.nodes.isEmpty && !p.loading) p.load().then((_) => p.testAll());
    }
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

  // ── 共享节点列表（与优质列表同款样式；按国家分组）──────────────────
  Widget _buildSharedBody(BuildContext context) {
    final p = context.watch<SharedNodeProvider>();
    if (p.nodes.isEmpty) {
      return Center(child: p.loading
          ? const CircularProgressIndicator()
          : Text(tr('暂无共享节点，点右上角刷新', 'No shared nodes — tap refresh'),
              style: TextStyle(color: msNow.textMuted)));
    }
    final zh = Brand.isZh;
    final groups = <String, List<FreeNode>>{};
    for (final n in p.nodes) {
      groups.putIfAbsent(freeCountryKey(n.name), () => []).add(n);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == '') return 1;
        if (b == '') return -1;
        return freeCountryLabel(a, zh).compareTo(freeCountryLabel(b, zh));
      });
    final rows = <dynamic>['__auto__'];   // 首项：智能选择
    for (final k in keys) { rows.add(k); rows.addAll(groups[k]!); }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final row = rows[i];
        if (row == '__auto__') {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SharedTile(
              name: p.autoTrying
                  ? tr('智能选择中…${p.tryingName ?? ''}', 'Auto-selecting… ${p.tryingName ?? ''}')
                  : tr('智能选择 · 自动挑选可用免费节点', 'Auto · pick a working free node'),
              latency: null, dead: false, connected: false, active: false,
              leadingIcon: Icons.bolt_rounded,
              onTap: p.autoTrying ? null : () {
                context.go('/home');
                context.read<SharedNodeProvider>().connectBest();
              },
            ),
          );
        }
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
            child: Row(children: [
              Text(freeCountryFlag(row).isEmpty ? '🌐' : freeCountryFlag(row), style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 7),
              Text(freeCountryLabel(row, zh),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: msNow.textSecondary)),
              const SizedBox(width: 6),
              Text('${(groups[row]!).length}',
                style: TextStyle(fontSize: 11, color: msNow.textSecondary.withOpacity(0.35))),
            ]),
          );
        }
        final n = row as FreeNode;
        final ms = p.latencyOf(n);
        final dead = ms != null && ms < 0;
        final active = identical(n, p.active);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SharedTile(
            name: freeLineName(n.name, n.server),
            latency: ms, dead: dead,
            connected: active && p.isConnected, active: active,
            onTap: dead ? null : () {
              // 手动点选：只连该节点、不自动跳转（跳转是「智能选择」的行为）。
              final shared = context.read<SharedNodeProvider>();
              context.go('/home');
              shared.connectVerified(n).then((ok) {
                if (!ok) {
                  rootMessengerKey.currentState?.showSnackBar(SnackBar(
                    content: Text(shared.error ??
                        tr('连接失败，请换一个节点', 'Connection failed, try another node')),
                    backgroundColor: kDanger,
                    duration: const Duration(seconds: 4),
                  ));
                }
              });
            },
          ),
        );
      },
    );
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
        backgroundColor: msNow.bg,
        surfaceTintColor: Colors.transparent,
        actions: [
          const MsTopControls(),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: tr('刷新延迟','Refresh latency'),
            onPressed: () {
              if (_tier == 'shared') {
                final p = context.read<SharedNodeProvider>();
                p.load().then((_) => p.testAll());
              } else {
                vpn.measureLatencies(servers);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: msNow.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: msNow.cardBorder),
              ),
              child: Row(children: [
                _TierChip(label: tr('优质节点·固定IP','Premium·Static IP'), selected: _tier == 'premium',
                  onTap: () => setState(() => _tier = 'premium')),
                _TierChip(
                  label: tr('免费节点·动态刷新','Free·Dynamic'), selected: _tier == 'shared',
                  onTap: () {
                    setState(() => _tier = 'shared');
                    final p = context.read<SharedNodeProvider>();
                    if (p.nodes.isEmpty && !p.loading) p.load().then((_) => p.testAll());
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
      body: _tier == 'shared'
          ? _buildSharedBody(context)
          : servers.isEmpty
          ? Center(child: Text(tr('暂无可用节点','No nodes available'), style: TextStyle(color: msNow.textMuted)))
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
          color: msNow.textSecondary.withOpacity(0.45)),
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
    default: return msNow.textMuted;
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
    final onBrand = Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white;
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? msNow.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? onBrand : msNow.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    ));
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
              color: (i < bars) ? color : msNow.textSecondary.withOpacity(0.12),
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
      color: isActive ? msNow.brand.withOpacity(0.18) : msNow.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(Icons.auto_awesome_rounded, color: msNow.brand, size: 26),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('智能选择','Auto select'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(tr('自动接入延迟最低、最空闲的节点','Picks the fastest, least busy node'),
                style: TextStyle(color: msNow.textSecondary.withOpacity(0.45), fontSize: 12)),
            ])),
            if (isActive)
              Icon(Icons.check_circle_rounded, color: msNow.brand, size: 20)
            else
              Icon(Icons.chevron_right_rounded, color: msNow.textSecondary.withOpacity(0.3)),
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
    // 状态显示：**以客户端实测可达性为准**（后端 status 可能过时/误报 offline）。
    //   仍在测量               → 转圈
    //   实测到延迟(可达)        → 信号格（即便后端报 offline，能测到就是能连）
    //   测不到 + 后端报离线      → 「离线」
    //   测不到 + 后端非离线      → 按 degraded 显示信号格（不误显示离线）
    final Widget statusW;
    if (!server.latencyMeasured) {
      statusW = SizedBox(width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, color: msNow.textSecondary.withOpacity(0.3)));
    } else if (dispLat != null) {
      statusW = _SignalBars(bars: bars);
    } else if (server.status == 'offline') {
      statusW = Text(tr('离线', 'offline'),
          style: const TextStyle(color: kDanger, fontSize: 13, fontWeight: FontWeight.w600));
    } else {
      statusW = _SignalBars(bars: server.status == 'degraded' ? 2 : 3);
    }
    return Material(
      color: isActive ? msNow.brand.withOpacity(0.18) : msNow.card,
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
                  style: TextStyle(color: msNow.textSecondary.withOpacity(0.5), fontSize: 12)),
              ]),
            ])),
            // 状态指示（信号格 / 离线 / 测量中），逻辑见上方 statusW。
            statusW,
            const SizedBox(width: 12),
            if (isActive)
              Icon(Icons.check_circle_rounded, color: msNow.brand, size: 20)
            else
              Icon(Icons.chevron_right_rounded, color: msNow.textSecondary.withOpacity(0.3)),
          ]),
        ),
      ),
    );
  }
}

// ── 共享节点 tile（与 _ServerTile 同款样式）────────────────────────────
class _SharedTile extends StatelessWidget {
  final String name;
  final int?   latency;   // ms（-1=超时，null=未测）
  final bool   dead, connected, active;
  final VoidCallback? onTap;
  final IconData? leadingIcon;   // 自定义左侧图标（智能选择用）
  const _SharedTile({
    required this.name, required this.latency, required this.dead,
    required this.connected, required this.active, required this.onTap,
    this.leadingIcon,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: (active && connected) ? msNow.brand.withOpacity(0.18) : msNow.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(leadingIcon ?? (connected ? Icons.check_circle_rounded : Icons.public_rounded),
              color: (leadingIcon != null) ? msNow.brand
                  : (connected ? msNow.brand : msNow.textSecondary.withOpacity(dead ? 0.25 : 0.55)), size: 24),
            const SizedBox(width: 14),
            Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15,
                color: dead ? msNow.textSecondary.withOpacity(0.35) : null))),
            _sharedLatencyBadge(latency),
            const SizedBox(width: 12),
            if (active && connected)
              Icon(Icons.check_circle_rounded, color: msNow.brand, size: 20)
            else
              Icon(Icons.chevron_right_rounded, color: msNow.textSecondary.withOpacity(0.3)),
          ]),
        ),
      ),
    );
  }
}

// 免费节点状态：参考优质节点用信号强度显示；超时(不可达)显示「爆满」。
Widget _sharedLatencyBadge(int? ms) {
  if (ms == null) return const SizedBox.shrink();
  if (ms < 0) return Text(tr('爆满', 'Full'),
      style: const TextStyle(color: kDanger, fontSize: 13, fontWeight: FontWeight.w600));
  final bars = ms < 100 ? 4 : (ms < 200 ? 3 : (ms < 300 ? 2 : 1));
  return _SignalBars(bars: bars);
}

