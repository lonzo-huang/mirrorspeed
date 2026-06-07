import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
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
      final servers = context.read<AuthProvider>().displayServers;
      context.read<VpnProvider>().measureLatencies(servers);
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
              itemCount: servers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _ServerTile(
                server:   servers[i],
                isActive: vpn.activeServer?.id == servers[i].id,
                onTap: () async {
                  Navigator.pop(context);
                  // 未登录或仅展示节点：连接前先登录（#1）
                  if (!auth.isLoggedIn || servers[i].isDisplayOnly) {
                    context.go('/login');
                    return;
                  }
                  if (vpn.isConnected) {
                    await vpn.switchServer(servers[i]);
                  } else {
                    await vpn.connect(servers[i]);
                  }
                },
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

  // 颜色阈值：<500 绿 · 500–1500 黄 · >1500 红 · 测量中灰（#6，不显示数值）
  Color _latencyColor(int? ms) {
    if (ms == null)  return Colors.white38;
    if (ms < 500)    return kSuccess;
    if (ms <= 1500)  return Colors.amber;
    return kDanger;
  }

  @override
  Widget build(BuildContext context) {
    final latency = server.latencyMs;
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
              if (Brand.isZh && server.location.isNotEmpty)
                Text(server.location, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
            ])),
            if (latency != null)
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: _latencyColor(latency), shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _latencyColor(latency).withOpacity(0.5), blurRadius: 6)],
                ),
              )
            else
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withOpacity(0.3)),
              ),
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
