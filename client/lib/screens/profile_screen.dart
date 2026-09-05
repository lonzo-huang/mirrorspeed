import 'invite_screen.dart';
import 'app_proxy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../services/api_service.dart';
import '../brand.dart';
import '../theme.dart';
import '../widgets/ms_top_controls.dart';
import '../version.dart';
import '../utils/portal_link.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final auth  = context.watch<AuthProvider>();
    final vpn   = context.watch<VpnProvider>();
    final user  = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '—';
    final isPaid = auth.dailyQuotaBytes == null;

    // 未登录：显示登录引导（#7，登录是可选的，从这里发起）
    if (!auth.isLoggedIn) {
      return Scaffold(
        backgroundColor: msNow.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          title: Text(tr('个人中心','Profile'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [msNow.brand, kBrandDark]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.person_outline_rounded, size: 36, color: msNow.textPrimary),
              ),
              const SizedBox(height: 20),
              Text(tr('登录后开始加速', 'Sign in to get started'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(tr('邮箱验证码登录，免费用户每日有时长额度',
                      'Email code sign-in. Free users get daily time.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: msNow.textSecondary.withOpacity(0.5), fontSize: 13)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: msNow.brand,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.login_rounded, size: 20),
                  label: Text(tr('登录 / 注册', 'Sign in / Sign up'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Text('MirrorSpeed VPN  v$kAppVersion',
                style: TextStyle(color: msNow.textSecondary.withOpacity(0.25), fontSize: 12)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: msNow.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('我的','Me'),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: const [Padding(padding: EdgeInsets.only(right: 16), child: MsTopControls())],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            children: [
              // ── 用户信息卡片 ────────────────────────────────
              _InfoCard(children: [
                _AvatarRow(email: email, isPaid: isPaid),
                const Divider(height: 1, color: Colors.white10),
                _InfoRow(icon: Icons.email_outlined, label: tr('邮箱', 'Email'), value: email),
                _InfoRow(
                  icon:       isPaid
                                ? Icons.workspace_premium_rounded
                                : Icons.person_outline_rounded,
                  label:      tr('账号类型', 'Account'),
                  value:      isPaid ? tr('付费会员', 'Premium') : tr('免费用户', 'Free'),
                  valueColor: isPaid ? msNow.brand : msNow.textMuted,
                ),
              ]),

              const SizedBox(height: 16),

              // ── 免费试用时长（按时间 #3）──────────────────────
              if (vpn.isFreeTrial) ...[
                _QuotaSection(
                  remainingSec: vpn.trialRemainingSec,
                  totalSec:     vpn.trialTotalSec,
                  exceeded:     vpn.quotaExceeded,
                ),
                const SizedBox(height: 16),
              ],

              // ── 升级卡片（免费用户）─────────────────────────
              if (!isPaid) ...[
                _UpgradeCard(),
                const SizedBox(height: 16),
              ],

              // 邀请好友已移至「设置 → 邀请好友」子页面（避免每次进「我的」重拉拖慢）。

              const SizedBox(height: 16),

              // ── 连接设置（只读信息，合并自原「设置」页）──────────
              _InfoCard(children: [
                _ConnModeRow(vpn: vpn),
                _InfoRow(icon: Icons.shield_outlined,    label: tr('加速协议', 'Acceleration protocol'),     value: 'MirrorTunnel V1.0'),
                _InfoRow(icon: Icons.lock_outline,       label: tr('加密', 'Encryption'),   value: 'ChaCha20'),
                _InfoRow(icon: Icons.blur_on_rounded,    label: tr('流量混淆', 'Obfuscation'), value: tr('已开启', 'On')),
                _InfoRow(icon: Icons.block_rounded,      label: tr('断网保护', 'Kill switch'), value: 'ON'),
                const _AppearanceRow(),
              ]),

              const SizedBox(height: 16),

              // ── 功能列表 ────────────────────────────────────
              _InfoCard(children: [
                _ActionRow(
                  icon:  Icons.card_giftcard_rounded,
                  label: tr('邀请好友', 'Invite friends'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InviteScreen())),
                ),
                _ActionRow(
                  icon:  Icons.apps_rounded,
                  label: tr('分应用代理（黑白名单）', 'Per-app proxy'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppProxyScreen())),
                ),
                _ActionRow(
                  icon:  Icons.error_outline_rounded,
                  label: vpn.error != null || auth.error != null
                      ? tr('错误信息 ●', 'Error info ●')
                      : tr('错误信息', 'Error info'),
                  onTap: () => _showErrorInfo(context),
                ),
                _ActionRow(
                  icon:  Icons.open_in_new_rounded,
                  label: tr('管理订阅', 'Manage subscription'),
                  onTap: () => openPortal('/dashboard'),
                ),
                _ActionRow(
                  icon:  Icons.privacy_tip_outlined,
                  label: tr('隐私政策', 'Privacy Policy'),
                  onTap: () => launchUrl(
                    Uri.parse('https://mirrorspeed.com/privacy'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _ActionRow(
                  icon:  Icons.description_outlined,
                  label: tr('服务条款', 'Terms of Service'),
                  onTap: () => launchUrl(
                    Uri.parse('https://mirrorspeed.com/terms'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _ActionRow(
                  icon:  Icons.help_outline_rounded,
                  label: tr('使用帮助', 'Help'),
                  onTap: () => context.push('/help'),   // 应用内 FAQ
                ),
              ]),

              const SizedBox(height: 16),

              // ── 退出登录 ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await _confirmLogout(context);
                    if (!ok) return;
                    if (vpn.isConnected) await vpn.disconnect();
                    await auth.signOut();
                  },
                  style: OutlinedButton.styleFrom(
                    side:           BorderSide(color: kDanger.withOpacity(0.5)),
                    foregroundColor: kDanger,
                    shape:          RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                    padding:        const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon:  const Icon(Icons.logout_rounded, size: 18),
                  label: Text(tr('退出登录', 'Sign out'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),

              const SizedBox(height: 10),

              // ── 退出程序（断开 VPN 并退出，从原右上角迁移至此）──────
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => _confirmExitApp(context),
                  style: TextButton.styleFrom(
                    foregroundColor: msNow.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon:  const Icon(Icons.power_settings_new_rounded, size: 18),
                  label: Text(tr('退出程序', 'Exit app'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),

              const SizedBox(height: 24),

              Text('MirrorSpeed VPN  v$kAppVersion',
                style: TextStyle(color: msNow.textSecondary.withOpacity(0.25),
                  fontSize: 12)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }


  // 退出程序：断开 VPN（清理隧道/路由）后退出 App。
  Future<void> _confirmExitApp(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: msNow.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('退出程序', 'Exit app')),
        content: Text(tr('该操作将会断开 VPN 并退出程序。',
                         'This will disconnect the VPN and exit the app.'),
          style: TextStyle(color: msNow.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel'), style: TextStyle(color: msNow.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('退出', 'Exit'), style: const TextStyle(color: kDanger))),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    try { await context.read<VpnProvider>().disconnect(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));  // 等原生隧道拆除
    await SystemNavigator.pop();
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: msNow.card,
        shape:           RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(16)),
        title:           Text(tr('退出登录', 'Sign out')),
        content:         Text(tr('确定要退出当前账号吗？', 'Sign out of this account?'),
                           style: TextStyle(color: msNow.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel'), style: TextStyle(color: msNow.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('退出', 'Sign out'), style: const TextStyle(color: kDanger)),
          ),
        ],
      ),
    ) ?? false;
  }
}

// ── 信息卡片容器 ──────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color:         msNow.card,
      borderRadius:  BorderRadius.circular(16),
      border:        Border.all(color: msNow.textSecondary.withOpacity(0.06)),
    ),
    child: Column(children: children),
  );
}

// ── 头像行 ────────────────────────────────────────────────────
class _AvatarRow extends StatelessWidget {
  final String email;
  final bool   isPaid;
  const _AvatarRow({required this.email, required this.isPaid});

  @override
  Widget build(BuildContext context) {
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [msNow.brand, kBrandDark],
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(initial,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: msNow.textPrimary)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:         (isPaid ? msNow.brand : msNow.textMuted).withOpacity(0.15),
                borderRadius:  BorderRadius.circular(20),
                border:        Border.all(
                                 color: (isPaid ? msNow.brand : msNow.textMuted)
                                            .withOpacity(0.35)),
              ),
              child: Text(
                isPaid ? tr('✦ 付费会员', '✦ Premium') : tr('免费用户', 'Free'),
                style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                  color:      isPaid ? msNow.brand : msNow.textMuted,
                ),
              ),
            ),
          ],
        )),
      ]),
    );
  }
}

// ── 信息行 ────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color?   valueColor;
  const _InfoRow({
    required this.icon, required this.label, required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(children: [
      Icon(icon, size: 17, color: msNow.textMuted),
      const SizedBox(width: 12),
      Text(label,
        style: TextStyle(color: msNow.textSecondary, fontSize: 14)),
      const Spacer(),
      Text(value,
        style: TextStyle(
          color:      valueColor ?? msNow.textPrimary,
          fontSize:   14,
          fontWeight: FontWeight.w500,
        )),
    ]),
  );
}

// 「错误信息」弹窗：集中展示配置/登录与连接错误（不再打扰主页）。
void _showErrorInfo(BuildContext context) {
  final auth = context.read<AuthProvider>();
  final vpn  = context.read<VpnProvider>();
  final items = <String>[];
  if (auth.error != null) items.add('${tr('配置 / 登录', 'Config / Login')}：${auth.error}');
  if (vpn.error  != null) items.add('${tr('连接', 'Connection')}：${vpn.error}');
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: msNow.card,
      title: Text(tr('错误信息', 'Error info'), style: const TextStyle(fontSize: 16)),
      content: items.isEmpty
          ? Text(tr('暂无错误信息 ✅', 'No errors ✅'),
              style: TextStyle(color: msNow.textSecondary.withOpacity(0.7), fontSize: 13))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in items)
                  Padding(padding: const EdgeInsets.only(bottom: 10),
                    child: SelectableText(e, style: const TextStyle(color: Colors.orange, fontSize: 13))),
              ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text(tr('关闭', 'Close'))),
      ],
    ),
  );
}

// ── 连接模式选择行 ───────────────────────────────────────────────
class _ConnModeRow extends StatelessWidget {
  final VpnProvider vpn;
  const _ConnModeRow({required this.vpn});

  String _desc(ConnMode m) {
    switch (m) {
      case ConnMode.auto:       return tr('直连优先，失败自动切换', 'Direct first, auto-fallback');
      case ConnMode.direct:     return tr('直连 UDP，速度最快', 'Direct UDP, fastest');
      case ConnMode.relay:      return tr('中继 443，抗封锁', 'Relay over 443');
      case ConnMode.cloudflare: return tr('Cloudflare 中继', 'Cloudflare relay');
    }
  }

  void _pick(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: msNow.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text(tr('连接模式', 'Connection mode'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ),
          for (final m in ConnMode.values)
            ListTile(
              leading: Icon(
                m == vpn.connMode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: m == vpn.connMode ? msNow.brand : msNow.textMuted, size: 22),
              title: Text(vpn.connModeLabel(m, Brand.isZh),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: Text(_desc(m),
                style: TextStyle(fontSize: 12, color: msNow.textSecondary.withOpacity(0.45))),
              onTap: () { Navigator.pop(ctx); vpn.setConnMode(m); },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _pick(context),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(Icons.swap_horiz_rounded, size: 17, color: msNow.textMuted),
        const SizedBox(width: 12),
        Text(tr('连接模式', 'Connection mode'),
          style: TextStyle(color: msNow.textSecondary, fontSize: 14)),
        const Spacer(),
        Text(vpn.connModeLabel(vpn.connMode, Brand.isZh),
          style: TextStyle(color: msNow.brand, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: msNow.textSecondary.withOpacity(0.3)),
      ]),
    ),
  );
}

// ── 外观行（浅色/深色 分段切换，与顶部主题按钮同源）──────────────
class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow();
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    Widget seg(String label, bool selected, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? msNow.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
          color: selected ? (theme.isDark ? Colors.black : Colors.white) : msNow.textSecondary)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(children: [
        Icon(Icons.light_mode_outlined, size: 17, color: msNow.textMuted),
        const SizedBox(width: 12),
        Text(tr('外观', 'Appearance'), style: TextStyle(color: msNow.textSecondary, fontSize: 14)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: msNow.bg, borderRadius: BorderRadius.circular(22),
            border: Border.all(color: msNow.cardBorder)),
          child: Row(children: [
            seg(tr('浅色', 'Light'), !theme.isDark, () { if (theme.isDark) theme.toggle(); }),
            seg(tr('深色', 'Dark'),  theme.isDark,  () { if (!theme.isDark) theme.toggle(); }),
          ]),
        ),
      ]),
    );
  }
}

// ── 操作行 ────────────────────────────────────────────────────
class _ActionRow extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap:        onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, size: 17, color: msNow.textMuted),
        const SizedBox(width: 12),
        Text(label,
          style: TextStyle(color: msNow.textSecondary, fontSize: 14)),
        const Spacer(),
        Icon(Icons.chevron_right_rounded,
          size: 18, color: msNow.textSecondary.withOpacity(0.2)),
      ]),
    ),
  );
}

// ── 免费试用时长（按时间）─────────────────────────────────────
class _QuotaSection extends StatelessWidget {
  final int  remainingSec;
  final int  totalSec;
  final bool exceeded;
  const _QuotaSection({required this.remainingSec, required this.totalSec, required this.exceeded});

  String _fmt(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = totalSec > 0 ? (remainingSec / totalSec).clamp(0.0, 1.0) : 0.0;
    final color = exceeded ? kDanger : (ratio < 0.2 ? Colors.amber : kSuccess);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:         color.withOpacity(0.08),
        borderRadius:  BorderRadius.circular(16),
        border:        Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timer_outlined, size: 15, color: color),
          const SizedBox(width: 6),
          Text(tr('今日免费时长', "Today's free time"),
            style: TextStyle(color: color, fontSize: 13,
              fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(exceeded
            ? tr('已用完', 'Used up')
            : tr('剩余 ${_fmt(remainingSec)}', '${_fmt(remainingSec)} left'),
            style: TextStyle(color: color, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value:           ratio,
            minHeight:       6,
            backgroundColor: msNow.textSecondary.withOpacity(0.08),
            valueColor:      AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ]),
    );
  }
}

// ── 升级卡片（免费用户）──────────────────────────────────────
class _UpgradeCard extends StatelessWidget {
  static const _upgradeUrl = 'https://mirrorspeed.com/pricing';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [msNow.brand.withOpacity(0.25), kBrandDark.withOpacity(0.15)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: msNow.brand.withOpacity(0.3)),
    ),
    child: Row(children: [
      Icon(Icons.workspace_premium_rounded, color: msNow.brand, size: 28),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('升级会员', 'Upgrade to Premium'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(tr('不限时长 · 全部节点 · 无广告', 'Unlimited time · All nodes · No ads'),
            style: TextStyle(color: msNow.textMuted, fontSize: 12)),
        ],
      )),
      FilledButton(
        onPressed: () => launchUrl(
          Uri.parse(_upgradeUrl),
          mode: LaunchMode.externalApplication,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: msNow.brand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(tr('升级', 'Upgrade'), style: const TextStyle(fontSize: 13)),
      ),
    ]),
  );
}

