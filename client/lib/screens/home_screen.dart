import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../env.dart';
import '../theme.dart';
import '../widgets/connect_button.dart';
import 'server_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vpn  = context.watch<VpnProvider>();

    final server = vpn.activeServer ?? (auth.servers.isNotEmpty ? auth.servers.first : null);

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
          Text(kIsCnFlavor ? '镜速加速器' : 'MirrorSpeed VPN',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新配置',
            onPressed: () => auth.refreshConfigs(),
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
                        key: ValueKey(vpn.status.name + vpn.isRelayMode.toString()),
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 15)),
              ),

              const Spacer(),

              // ── 智能 / 全局 模式切换（仅中文版）─────────────────
              if (kIsCnFlavor) ...[
                _RoutingModeToggle(
                  mode:      vpn.routingMode,
                  onChanged: (m) => vpn.setRoutingMode(m),
                ),
                const SizedBox(height: 16),
              ],

              // ── 当前节点卡片 ──────────────────────────────────
              if (server != null) _ServerCard(
                server:   server,
                isActive: vpn.isConnected,
                onTap:    () => _showServerList(context),
              ),

              const SizedBox(height: 12),

              // ── 切换节点按钮 ──────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showServerList(context),
                  style: OutlinedButton.styleFrom(
                    side:           BorderSide(color: Colors.white.withOpacity(0.15)),
                    shape:          RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                    padding:        const EdgeInsets.symmetric(vertical: 13),
                    foregroundColor: Colors.white70,
                  ),
                  icon:  const Icon(Icons.language_rounded, size: 18),
                  label: Text('选择节点 (${auth.servers.length} 个可用)'),
                ),
              ),

              const SizedBox(height: 12),

              // ── 流量进度条（免费用户）────────────────────────────
              if (auth.dailyQuotaBytes != null)
                _QuotaBar(
                  used:      auth.dailyBytesUsed,
                  quota:     auth.dailyQuotaBytes!,
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
    if (vpn.status == VpnStatus.connecting) {
      return vpn.isRelayMode ? '切换为强力模式连接中…' : '快速模式连接中…';
    }
    return switch (vpn.status) {
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
      child: Text('${(ms / 10).round()}ms', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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

  static const _pricingUrl = 'https://mirrorspeed.com/pricing';

  @override
  Widget build(BuildContext context) => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin:  const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:         kDanger.withOpacity(0.1),
        borderRadius:  BorderRadius.circular(12),
        border:        Border.all(color: kDanger.withOpacity(0.3)),
      ),
      child: const Row(children: [
        Icon(Icons.block_rounded, color: kDanger, size: 16),
        SizedBox(width: 8),
        Expanded(
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
          shape:   RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon:  const Icon(Icons.workspace_premium_rounded, size: 20),
        label: const Text('升级专业版 · 无限流量',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    ),
  ]);
}

// ── 智能 / 全局 模式切换 Toggle ──────────────────────────────────────────────
class _RoutingModeToggle extends StatelessWidget {
  final RoutingMode              mode;
  final ValueChanged<RoutingMode> onChanged;
  const _RoutingModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color:        kCard,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(children: [
        _ToggleItem(
          label:    '智能模式',
          icon:     Icons.psychology_rounded,
          selected: mode == RoutingMode.smart,
          onTap:    () => onChanged(RoutingMode.smart),
          tooltip:  '中国IP直连，境外走VPN',
        ),
        _ToggleItem(
          label:    '全局模式',
          icon:     Icons.public_rounded,
          selected: mode == RoutingMode.global,
          onTap:    () => onChanged(RoutingMode.global),
          tooltip:  '所有流量走VPN',
        ),
      ]),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final bool         selected;
  final VoidCallback onTap;
  final String       tooltip;
  const _ToggleItem({
    required this.label, required this.icon, required this.selected,
    required this.onTap, required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin:       const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color:        selected ? kBrand.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border:       selected
                  ? Border.all(color: kBrand.withOpacity(0.5))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14,
                  color: selected ? kBrand : Colors.white.withOpacity(0.4)),
                const SizedBox(width: 5),
                Text(label,
                  style: TextStyle(
                    fontSize:   13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color:      selected ? kBrand : Colors.white.withOpacity(0.4),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
