import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/ad_service.dart';
import '../brand.dart';
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

    final server = vpn.activeServer ?? (auth.displayServers.isNotEmpty ? auth.displayServers.first : null);

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
          Text(Brand.appName,
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
              // ── 全局通告（运营下发）#2 ────────────────────────
              if (auth.announcement != null)
                _AnnouncementBanner(data: auth.announcement!),

              // ── 新版本提示 #2 ─────────────────────────────────
              if (auth.updateAvailable)
                _UpdateBanner(version: auth.latestVersion!),

              // ── 订阅到期提醒 banner ───────────────────────────
              if (auth.daysUntilExpiry != null && auth.daysUntilExpiry! <= 7)
                _ExpiryBanner(days: auth.daysUntilExpiry!),

              const SizedBox(height: 32),

              // ── 连接按钮（超额时改为升级按钮）──────────────────
              if (vpn.quotaExceeded && !vpn.isConnected) ...[
                _UpgradeButton(),
                const SizedBox(height: 10),
                const _AdExtendButton(),
              ]
              else
                ConnectButton(
                  status: vpn.status,
                  onPressed: vpn.isBusy ? null : () async {
                    if (vpn.isConnected) {
                      await vpn.disconnect();
                    } else if (!auth.isLoggedIn || server == null || server.isDisplayOnly) {
                      // 未登录（或只有公开展示节点）：连接前先登录（#1/#7）
                      context.go('/login');
                    } else {
                      await vpn.connect(server);
                    }
                  },
                ),

              const SizedBox(height: 32),

              // ── 状态文字（连接中 / 模式·已连接；不再显示连接时长）──────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(vpn.statusLine,
                    key: ValueKey(vpn.status.name + vpn.protocol.name),
                    style: TextStyle(
                      color: vpn.isConnected ? kSuccess : Colors.white.withOpacity(0.6),
                      fontSize: vpn.isConnected ? 20 : 15,
                      fontWeight: vpn.isConnected ? FontWeight.w600 : FontWeight.normal,
                    )),
              ),

              const Spacer(),

              // ── 智能 / 全局 模式切换（仅中文版）─────────────────
              if (Brand.showSmartRouting) ...[
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
                  label: Text('选择节点 (${auth.displayServers.length} 个可用)'),
                ),
              ),

              const SizedBox(height: 12),

              // ── 免费试用倒计时（按时间 #3）+ 看广告延长（#4）──────────
              if (vpn.isFreeTrial) ...[
                _TrialBar(
                  remainingSec: vpn.trialRemainingSec,
                  totalSec:     vpn.trialTotalSec,
                  exceeded:     vpn.quotaExceeded,
                ),
                const SizedBox(height: 8),
                const _AdExtendButton(compact: true),
              ],

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

}

// 延迟用颜色点表示，不显示具体数值（#6）：
//   <500ms 绿色 · 500–1500ms 黄色 · >1500ms 红色 · 测量中灰色
Color latencyColor(int? ms) {
  if (ms == null)   return Colors.white38;
  if (ms < 500)     return kSuccess;
  if (ms <= 1500)   return Colors.amber;
  return kDanger;
}

class LatencyDot extends StatelessWidget {
  final int? ms;
  const LatencyDot({super.key, required this.ms});
  @override
  Widget build(BuildContext context) {
    final c = latencyColor(ms);
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: c, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)],
      ),
    );
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
          LatencyDot(ms: server.latencyMs as int?),
          const SizedBox(width: 10),
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

// ── 免费试用倒计时条（按时间）────────────────────────────────────────────────
class _TrialBar extends StatelessWidget {
  final int  remainingSec;
  final int  totalSec;
  final bool exceeded;
  const _TrialBar({ required this.remainingSec, required this.totalSec, required this.exceeded });

  String _fmt(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = totalSec > 0 ? (remainingSec / totalSec).clamp(0.0, 1.0) : 0.0;
    final color = exceeded ? kDanger : (ratio < 0.2 ? Colors.amber : kSuccess);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timer_outlined, size: 13, color: color),
          const SizedBox(width: 6),
          Text('今日免费时长', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            exceeded ? '已用完' : '剩余 ${_fmt(remainingSec)}',
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

// ── 看广告延长时长按钮（激励视频，仅 Android/iOS）──────────────────────────────
class _AdExtendButton extends StatefulWidget {
  final bool compact;
  const _AdExtendButton({ this.compact = false });
  @override State<_AdExtendButton> createState() => _AdExtendButtonState();
}

class _AdExtendButtonState extends State<_AdExtendButton> {
  bool _busy = false;

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    AdService.instance.showRewarded(
      onReward: () => vpn.addAdBonusMinutes(kAdRewardMinutes),
      onClosed: (rewarded) {
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(
          content: Text(rewarded ? '已增加 $kAdRewardMinutes 分钟免费时长 🎉' : '广告未加载好，请稍后再试'),
          backgroundColor: rewarded ? kSuccess : kDanger,
          duration: const Duration(seconds: 2),
        ));
      },
    );
    // 兜底：showRewarded 未就绪会立刻 onClosed(false)，这里防止卡在 busy
    await Future.delayed(const Duration(seconds: 1));
    if (mounted && _busy) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = '看广告 +$kAdRewardMinutes 分钟';
    if (widget.compact) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: _busy ? null : _watch,
          icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: kBrand),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _watch,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: kBrand.withOpacity(0.5)),
          foregroundColor: kBrand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 13),
        ),
        icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
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

// ── 新版本提示 banner（#2）────────────────────────────────────────────────────
class _UpdateBanner extends StatelessWidget {
  final String version;
  const _UpdateBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.mirrorspeed.com/download'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        width: double.infinity,
        margin:  const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        kBrand.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: kBrand.withOpacity(0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.system_update_rounded, color: kBrand, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('发现新版本 v$version，点击前往下载更新',
            style: const TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.w500))),
          const Text('更新 →', style: TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

// ── 全局通告 banner（#2，运营在 Supabase 下发）────────────────────────────────
class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnnouncementBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '') as String;
    final body  = (data['body']  ?? '') as String;
    final level = (data['level'] ?? 'info') as String;
    final color = level == 'warning' ? Colors.amber
                : level == 'critical' ? kDanger
                : kBrand;
    final url   = data['url'] as String?;
    final w = Container(
      width: double.infinity,
      margin:  const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.campaign_rounded, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty)
            Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(body, style: TextStyle(color: color.withOpacity(0.9), fontSize: 12)),
            ),
        ])),
      ]),
    );
    if (url != null && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: w,
      );
    }
    return w;
  }
}

// ── 订阅到期提醒 banner ───────────────────────────────────────────────────────
class _ExpiryBanner extends StatelessWidget {
  final int days;
  const _ExpiryBanner({required this.days});

  @override
  Widget build(BuildContext context) {
    final isUrgent = days <= 2;
    final color    = isUrgent ? kDanger : Colors.amber;
    final icon     = isUrgent
        ? Icons.warning_rounded
        : Icons.access_time_rounded;
    final text     = days == 0
        ? '您的订阅今天到期，请尽快续费'
        : '您的订阅将在 $days 天后到期';

    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://mirrorspeed.com/dashboard/billing'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        width: double.infinity,
        margin:  const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Text('续费 →',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
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
