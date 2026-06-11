import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// 返回键 → 退到后台（不退出应用，VPN 保持运行）；退出由右上角退出键负责。
const MethodChannel _lifecycleChannel = MethodChannel('com.mirrorspeed.app/lifecycle');
Future<void> _moveAppToBackground() async {
  try { await _lifecycleChannel.invokeMethod('moveToBackground'); } catch (_) {}
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vpn  = context.watch<VpnProvider>();

    // 优先用真实节点（已登录配置已加载）；否则退回展示节点（公开列表）。
    final realServers = auth.displayServers.where((s) => !s.isDisplayOnly).toList();
    final server = vpn.activeServer ??
        (realServers.isNotEmpty
            ? realServers.first
            : (auth.displayServers.isNotEmpty ? auth.displayServers.first : null));

    return PopScope(
      // 返回键不退出应用：拦截后退到后台（合规且保持连接）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _moveAppToBackground();
      },
      child: Scaffold(
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
            icon: const Icon(Icons.power_settings_new_rounded, size: 20),
            tooltip: tr('退出', 'Exit'),
            onPressed: () => _confirmExit(context),
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
                    } else if (!auth.isLoggedIn) {
                      context.go('/login');            // 未登录 → 去登录
                    } else if (server == null || server.isDisplayOnly) {
                      // 已登录但真实配置还没就绪 → 拉取配置（不要跳登录，否则按钮像点不动）
                      await auth.refreshConfigs();
                    } else if (vpn.autoSelect) {
                      // 智能分配：综合延迟+负载自动挑节点
                      await vpn.connectAuto(realServers);
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
                  label: Text(tr('选择节点 (${auth.displayServers.length} 个可用)',
                               'Select node (${auth.displayServers.length} available)')),
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
                    Expanded(child: Text(tr('配置获取失败: ${auth.error}', 'Failed to load config: ${auth.error}'),
                      style: const TextStyle(color: Colors.orange, fontSize: 12))),
                  ]),
                ),

              // ── VPN 提示（权限提醒用橙色，真实错误用红色）────────
              if (vpn.error != null) _VpnErrorBanner(message: vpn.error!),
            ],
          ),
        ),
      ),
      ),   // Scaffold
    );     // PopScope
  }

  Future<void> _confirmExit(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('退出应用', 'Exit app')),
        content: Text(tr('退出后将断开连接。返回键只会回到后台，连接保持。',
                         'Exiting disconnects the VPN. The back button only sends the app to the background and keeps the connection.'),
          style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel'), style: const TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('退出', 'Exit'), style: const TextStyle(color: kDanger))),
        ],
      ),
    ) ?? false;
    if (ok) {
      // 强制断开并清理隧道/路由后再退出（#3）。
      try { await context.read<VpnProvider>().disconnect(); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500)); // 等原生隧道完全拆除
      await SystemNavigator.pop();
    }
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
            Text(Brand.isZh ? server.displayName
                            : (server.location.isNotEmpty ? server.location : server.displayName),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (Brand.isZh && server.location.isNotEmpty)
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
          Text(tr('今日免费时长', "Today's free time"), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            exceeded ? tr('已用完', 'Used up') : tr('剩余 ${_fmt(remainingSec)}', '${_fmt(remainingSec)} left'),
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

  @override
  void initState() {
    super.initState();
    // 预热激励广告，确保用户点击时已缓存好、能立刻播放（#4）。
    AdService.instance.warmUp();
  }

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    AdService.instance.showRewarded(
      onClosed: (earned, watchedSec) async {
        if (!mounted) return;
        setState(() => _busy = false);
        if (!earned) {
          messenger.showSnackBar(SnackBar(
            content: Text(tr('广告未加载好或未看完，请重试', 'Ad not ready or not completed, please retry')),
            backgroundColor: kDanger, duration: const Duration(seconds: 2)));
          return;
        }
        final granted = await vpn.addAdWatch(watchedSec);
        messenger.showSnackBar(SnackBar(
          content: Text(granted
            ? tr('已解锁 +$kAdRewardMinutes 分钟免费时长 🎉', 'Unlocked +$kAdRewardMinutes min of free time 🎉')
            : tr('已观看 ${vpn.adProgressSec}/${vpn.adRequiredSec} 秒，再看一条解锁',
                 'Watched ${vpn.adProgressSec}/${vpn.adRequiredSec}s — watch one more to unlock')),
          backgroundColor: granted ? kSuccess : kBrand,
          duration: const Duration(seconds: 2),
        ));
      },
    );
    // 兜底：showRewarded 未就绪会立刻 onClosed(false,0)，防止卡在 busy
    await Future.delayed(const Duration(seconds: 1));
    if (mounted && _busy) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    // 满 60s 才发放，按钮上显示进度（已看 X/60s）。
    final progress = vpn.adProgressSec > 0 ? ' (${vpn.adProgressSec}/${vpn.adRequiredSec}s)' : '';
    final label = tr('看广告解锁 +$kAdRewardMinutes 分钟$progress', 'Watch ads +$kAdRewardMinutes min$progress');
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
      child: Row(children: [
        const Icon(Icons.block_rounded, color: kDanger, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tr('今日免费时长已用完，明日自动恢复', "Today's free time is used up. Resets tomorrow."),
            style: const TextStyle(color: kDanger, fontSize: 12)),
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
        label: Text(tr('升级会员 · 无限时长', 'Upgrade · Unlimited'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
          Expanded(child: Text(tr('发现新版本 v$version，点击前往下载更新', 'New version v$version available — tap to update'),
            style: const TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.w500))),
          Text(tr('更新 →', 'Update →'), style: const TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.bold)),
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
        ? tr('您的订阅今天到期，请尽快续费', 'Your subscription expires today — please renew')
        : tr('您的订阅将在 $days 天后到期', 'Your subscription expires in $days days');

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
          Text(tr('续费 →', 'Renew →'),
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
