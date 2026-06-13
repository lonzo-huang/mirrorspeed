import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_service.dart';
import '../brand.dart';
import '../theme.dart';

class ServerListScreen extends StatefulWidget {
  const ServerListScreen({super.key});
  @override State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
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
  }

  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final vpn     = context.watch<VpnProvider>();
    final servers = auth.displayServers;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('选择节点','Select node'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: tr('刷新延迟','Refresh latency'),
            onPressed: () => vpn.measureLatencies(servers),
          ),
        ],
      ),
      body: servers.isEmpty
          ? Center(child: Text(tr('暂无可用节点','No nodes available'), style: const TextStyle(color: Colors.white54)))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              // +1：列表首项为「智能选择」
              itemCount: servers.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                      Navigator.pop(context);
                      await vpn.connectAuto(servers);
                    },
                  );
                }
                final server = servers[i - 1];
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
                    Navigator.pop(context);
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

// ── 三档负载色块通用工具 ─────────────────────────────────────────────
// tier: 0 空闲(绿) · 1 适中(黄) · 2 繁忙(红)
Color _loadColor(int tier) =>
    tier == 0 ? kSuccess : (tier == 1 ? Colors.amber : kDanger);
String _loadLabel(int tier) => tier == 0
    ? tr('空闲','Idle')
    : (tier == 1 ? tr('适中','Busy') : tr('繁忙','Full'));

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

  // 延迟颜色：<=100 绿 · 101–300 黄 · >300 红（截断显示 >300ms）· 无样本灰
  Color _latencyColor(int? ms) {
    if (ms == null) return Colors.white38;
    if (ms <= 100)  return kSuccess;
    if (ms <= 300)  return Colors.amber;
    return kDanger;
  }

  String _latencyText(int? ms) {
    if (ms == null) return '—';
    if (ms > 300)   return '>300ms';
    return '${ms}ms';
  }

  @override
  Widget build(BuildContext context) {
    final latency = server.latencyMs;
    final tier    = server.loadTier;
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
            // 延迟数值（10 秒滚动平均）。测量中→转圈；测量完成但失败→超时（不再永久转圈）。
            if (server.latencyMeasured || server.status == 'offline')
              Text(
                server.latencyMs == null ? tr('超时','timeout') : _latencyText(latency),
                style: TextStyle(
                  color: server.latencyMs == null ? kDanger : _latencyColor(latency),
                  fontSize: 13, fontWeight: FontWeight.w600))
            else
              SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withOpacity(0.3))),
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
