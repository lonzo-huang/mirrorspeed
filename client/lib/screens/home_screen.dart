import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../theme.dart';
import '../widgets/connect_button.dart';
import 'server_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vpn  = context.watch<VpnProvider>();

    final server  = vpn.activeServer ?? (auth.servers.isNotEmpty ? auth.servers.first : null);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kBrand, kBrandDark]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('MirrorSpeed VPN', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新配置',
            onPressed: () => auth.refreshConfigs(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: kCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) async {
              if (v == 'logout') {
                if (vpn.isConnected) await vpn.disconnect();
                await auth.signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'device',
                child: Row(children: [
                  const Icon(Icons.devices_rounded, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  Text(auth.deviceLabel ?? '我的设备', style: const TextStyle(fontSize: 13)),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_rounded, size: 18, color: kDanger),
                  SizedBox(width: 10),
                  Text('退出登录', style: TextStyle(color: kDanger, fontSize: 13)),
                ]),
              ),
            ],
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // ── 连接按钮（超额时改为升级按钮）──────────────────
              if (auth.isSuspended && !vpn.isConnected)
                _UpgradeButton()
              else
                ConnectButton(
                  status: vpn.status,
                  onPressed: vpn.isBusy ? null : () async {
                    if (vpn.isConnected) {
                      await vpn.disconnect();
                    } else if (server != null) {
                      await vpn.connect(server);
                    }
                  },
                ),

              const SizedBox(height: 32),

              // ── 计时器 / 状态文字 ─────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: vpn.isConnected
                    ? Text(vpn.elapsedFormatted,
                        key: const ValueKey('timer'),
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w200,
                          fontFeatures: [FontFeature.tabularFigures()]))
                    : Text(_statusText(vpn),
                        key: const ValueKey('status'),
                        style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 15)),
              ),

              // ── 中继模式标识徽章 ──────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: vpn.isRelayMode
                    ? Padding(
                        key: const ValueKey('relay-badge'),
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amber.withOpacity(0.35)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.alt_route_rounded, size: 13, color: Colors.amber),
                            const SizedBox(width: 5),
                            Text(
                              vpn.isConnected ? 'WebSocket 中继' : '切换 WebSocket 中继…',
                              style: const TextStyle(color: Colors.amber, fontSize: 11,
                                fontWeight: FontWeight.w600),
                            ),
                          ]),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-badge')),
              ),

              const Spacer(),

              // ── 当前节点卡片 ──────────────────────────────────
              if (server != null) _ServerCard(
                server:    server,
                isActive:  vpn.isConnected,
                onTap: () => _showServerList(context),
              ),

              const SizedBox(height: 16),

              // ── 切换节点按钮 ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showServerList(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.15)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Colors.white70,
                  ),
                  icon: const Icon(Icons.language_rounded, size: 18),
                  label: Text('选择节点 (${auth.servers.length} 个可用)'),
                ),
              ),

              const SizedBox(height: 16),

              // ── 流量进度条（免费用户显示）────────────────────────
              if (auth.dailyQuotaBytes != null)
                _QuotaBar(
                  used:  auth.dailyBytesUsed,
                  quota: auth.dailyQuotaBytes!,
                  suspended: auth.isSuspended,
                ),

              const SizedBox(height: 8),

              // ── Auth 错误提示（配置获取失败）──────────────────
              if (auth.error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text('配置获取失败: ${auth.error}',
                      style: const TextStyle(color: Colors.orange, fontSize: 12))),
                  ]),
                ),

              // ── VPN 提示（权限提醒用橙色，真实错误用红色）────────
              if (vpn.error != null) _VpnErrorBanner(message: vpn.error!),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerList(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: const ServerListScreen(),
      ),
    );
  }

  String _statusText(VpnProvider vpn) {
    if (vpn.status == VpnStatus.connecting && vpn.isRelayMode) {
      return '正在通过中继连接…';
    }
    return switch (vpn.status) {
      VpnStatus.connecting    => '正在建立连接…',
      VpnStatus.disconnecting => '正在断开…',
      VpnStatus.error         => '连接出错',
      _                       => '未连接',
    };
  }
}

class _ServerCard extends StatelessWidget {
  final dynamic server;
  final bool     isActive;
  final VoidCallback onTap;
  const _ServerCard({ required this.server, required this.isActive, required this.onTap });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? kSuccess.withOpacity(0.4) : Colors.white.withOpacity(0.06),
          ),
          boxShadow: isActive
              ? [BoxShadow(color: kSuccess.withOpacity(0.1), blurRadius: 20)]
              : [],
        ),
        child: Row(children: [
          Text(server.flagEmoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(server.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (server.location.isNotEmpty)
              Text(server.location, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12)),
          ])),
          if (server.latencyMs != null)
            _LatencyBadge(ms: server.latencyMs as int),
          const SizedBox(width: 8),
          Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4)),
        ]),
      ),
    );
  }
}

class _VpnErrorBanner extends StatelessWidget {
  final String message;
  const _VpnErrorBanner({required this.message});

  bool get _isPermission => message.contains('请在刚才弹出');

  @override
  Widget build(BuildContext context) {
    final color = _isPermission ? Colors.orange : kDanger;
    final icon  = _isPermission
        ? Icons.admin_panel_settings_outlined
        : Icons.error_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
          style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  final int ms;
  const _LatencyBadge({ required this.ms });

  Color get color {
    if (ms < 100) return kSuccess;
    if (ms < 250) return Colors.amber;
    return kDanger;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('${ms}ms', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ── 流量进度条 ───────────────────────────────────────────────────────────────
class _QuotaBar extends StatelessWidget {
  final int  used;
  final int  quota;
  final bool suspended;
  const _QuotaBar({ required this.used, required this.quota, required this.suspended });

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (used / quota).clamp(0.0, 1.0);
    final color = suspended
        ? kDanger
        : ratio > 0.8 ? Colors.amber : kSuccess;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.data_usage_rounded, size: 13, color: color),
          const SizedBox(width: 6),
          Text('今日免费流量', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            suspended ? '已用完' : '${_fmt(used)} / ${_fmt(quota)}',
            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ]),
    );
  }
}

// ── 超额升级按钮 ──────────────────────────────────────────────────────────────
class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton();

  static const _pricingUrl = 'https://mirrorspeed.mirrorquant.com/pricing';

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: kDanger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDanger.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.block_rounded, color: kDanger, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('今日免费流量已用完，明日自动恢复',
              style: TextStyle(color: kDanger, fontSize: 12)),
          ),
        ]),
      ),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(_pricingUrl),
            mode: LaunchMode.externalApplication,
          ),
          style: FilledButton.styleFrom(
            backgroundColor: kBrand,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.workspace_premium_rounded, size: 20),
          label: const Text('升级专业版 · 无限流量', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ),
    ]);
  }
}
