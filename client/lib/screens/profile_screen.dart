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
import '../version.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _referralFuture;

  @override
  void initState() {
    super.initState();
    _referralFuture = ApiService.instance.fetchReferralInfo();
  }

  void _refreshReferral() => setState(() {
    _referralFuture = ApiService.instance.fetchReferralInfo();
  });

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
        backgroundColor: kBg,
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
                  gradient: const LinearGradient(colors: [kBrand, kBrandDark]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.person_outline_rounded, size: 36, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(tr('登录后开始加速', 'Sign in to get started'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(tr('邮箱验证码登录，免费用户每日有时长额度',
                      'Email code sign-in. Free users get daily time.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrand,
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
                style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 12)),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('个人中心','Profile'),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
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
                  valueColor: isPaid ? kBrand : Colors.white54,
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

              // ── 邀请好友模块 ────────────────────────────────
              FutureBuilder<Map<String, dynamic>>(
                future: _referralFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const _InviteCardSkeleton();
                  }
                  if (snap.hasError || !snap.hasData) {
                    return const SizedBox.shrink();
                  }
                  return _InviteCard(
                    data:           snap.data!,
                    onApplyCode:    () => _showApplyCodeDialog(context),
                    onRefresh:      _refreshReferral,
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── 功能列表 ────────────────────────────────────
              _InfoCard(children: [
                _ActionRow(
                  icon:  Icons.open_in_new_rounded,
                  label: tr('管理订阅', 'Manage subscription'),
                  onTap: () => launchUrl(
                    Uri.parse('https://mirrorspeed.com/dashboard'),
                    mode: LaunchMode.externalApplication,
                  ),
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
                  onTap: () => launchUrl(
                    Uri.parse('https://mirrorspeed.com/help'),
                    mode: LaunchMode.externalApplication,
                  ),
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

              const SizedBox(height: 24),

              Text('MirrorSpeed VPN  v$kAppVersion',
                style: TextStyle(color: Colors.white.withOpacity(0.25),
                  fontSize: 12)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showApplyCodeDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('输入邀请码', 'Enter referral code')),
        content: TextField(
          controller:    ctrl,
          autofocus:     true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText:    tr('例如：MX7K9P', 'e.g. MX7K9P'),
            hintStyle:   const TextStyle(color: Colors.white38),
          ),
          style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel'), style: const TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ApiService.instance.applyReferralCode(code);
                _refreshReferral();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('邀请码绑定成功 🎉', 'Referral code applied 🎉')),
                      backgroundColor: kSuccess),
                  );
                }
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message),
                      backgroundColor: kDanger),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: kBrand),
            child: Text(tr('确认', 'Confirm')),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape:           RoundedRectangleBorder(
                           borderRadius: BorderRadius.circular(16)),
        title:           Text(tr('退出登录', 'Sign out')),
        content:         Text(tr('确定要退出当前账号吗？', 'Sign out of this account?'),
                           style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消', 'Cancel'), style: const TextStyle(color: Colors.white54)),
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
      color:         kCard,
      borderRadius:  BorderRadius.circular(16),
      border:        Border.all(color: Colors.white.withOpacity(0.06)),
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
            gradient: const LinearGradient(
              colors: [kBrand, kBrandDark],
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(initial,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: Colors.white)),
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
                color:         (isPaid ? kBrand : Colors.white24).withOpacity(0.15),
                borderRadius:  BorderRadius.circular(20),
                border:        Border.all(
                                 color: (isPaid ? kBrand : Colors.white38)
                                            .withOpacity(0.35)),
              ),
              child: Text(
                isPaid ? tr('✦ 付费会员', '✦ Premium') : tr('免费用户', 'Free'),
                style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                  color:      isPaid ? kBrand : Colors.white54,
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
      Icon(icon, size: 17, color: Colors.white38),
      const SizedBox(width: 12),
      Text(label,
        style: const TextStyle(color: Colors.white70, fontSize: 14)),
      const Spacer(),
      Text(value,
        style: TextStyle(
          color:      valueColor ?? Colors.white,
          fontSize:   14,
          fontWeight: FontWeight.w500,
        )),
    ]),
  );
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
        Icon(icon, size: 17, color: Colors.white38),
        const SizedBox(width: 12),
        Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const Spacer(),
        Icon(Icons.chevron_right_rounded,
          size: 18, color: Colors.white.withOpacity(0.2)),
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
            backgroundColor: Colors.white.withOpacity(0.08),
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
        colors: [kBrand.withOpacity(0.25), kBrandDark.withOpacity(0.15)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border:       Border.all(color: kBrand.withOpacity(0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.workspace_premium_rounded, color: kBrand, size: 28),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('升级会员', 'Upgrade to Premium'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(tr('不限时长 · 全部节点 · 无广告', 'Unlimited time · All nodes · No ads'),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      )),
      FilledButton(
        onPressed: () => launchUrl(
          Uri.parse(_upgradeUrl),
          mode: LaunchMode.externalApplication,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: kBrand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(tr('升级', 'Upgrade'), style: const TextStyle(fontSize: 13)),
      ),
    ]),
  );
}

// ── 邀请好友卡片 ──────────────────────────────────────────────
class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback         onApplyCode;
  final VoidCallback         onRefresh;
  const _InviteCard({
    required this.data,
    required this.onApplyCode,
    required this.onRefresh,
  });

  String get _code         => data['referral_code']    as String? ?? '—';
  String get _shareUrl     => data['share_url']         as String? ?? '';
  int    get _inviteCount  => data['invite_count']      as int?    ?? 0;
  int    get _bonusDays    => data['total_bonus_days']  as int?    ?? 0;
  String? get _expiresAt  => data['bonus_expires_at']  as String?;
  String? get _referredBy => data['referred_by_code']  as String?;

  String get _expiryLabel {
    if (_expiresAt == null) return '';
    final dt  = DateTime.tryParse(_expiresAt!) ?? DateTime.now();
    final now = DateTime.now();
    if (dt.isBefore(now)) return '';
    final days = dt.difference(now).inDays;
    return tr('（还剩 $days 天）', '($days d left)');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C3AED).withOpacity(0.18),
            const Color(0xFF2563EB).withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题行
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            const Icon(Icons.card_giftcard_rounded,
              color: Color(0xFFA78BFA), size: 18),
            const SizedBox(width: 8),
            Text(tr('邀请好友', 'Invite friends'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: Color(0xFFA78BFA))),
            const Spacer(),
            // 刷新按钮
            GestureDetector(
              onTap: onRefresh,
              child: Icon(Icons.refresh_rounded,
                color: Colors.white.withOpacity(0.35), size: 18),
            ),
          ]),
        ),

        // 统计数字
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            _StatChip(label: tr('已邀请', 'Invited'), value: tr('$_inviteCount 人', '$_inviteCount')),
            const SizedBox(width: 12),
            _StatChip(label: tr('累计获得', 'Earned'), value: tr('$_bonusDays 天', '$_bonusDays d')),
            if (_expiryLabel.isNotEmpty) ...[
              const SizedBox(width: 12),
              _StatChip(label: tr('奖励', 'Bonus'), value: _expiryLabel, accent: true),
            ],
          ]),
        ),

        const Divider(height: 1, color: Colors.white10),

        // 邀请码 + 复制/分享
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('你的邀请码', 'Your invite code'),
                style: TextStyle(color: Colors.white.withOpacity(0.5),
                  fontSize: 11)),
              const SizedBox(height: 4),
              Text(_code,
                style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold,
                  letterSpacing: 6, color: Color(0xFFE2E8F0),
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
            ]),
            const Spacer(),
            // 复制按钮
            _IconBtn(
              icon:    Icons.copy_rounded,
              tooltip: tr('复制邀请码', 'Copy code'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: _code));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('邀请码已复制', 'Code copied')),
                    duration: const Duration(seconds: 1)),
                );
              },
            ),
            const SizedBox(width: 8),
            // 分享按钮：调起系统分享(复制/微信/WhatsApp 等)
            _IconBtn(
              icon:    Icons.share_rounded,
              tooltip: tr('分享', 'Share'),
              onTap: () {
                if (_shareUrl.isEmpty) return;
                final msg = tr(
                  '我在用 MirrorSpeed，高速又稳定，一起来用吧！邀请码 $_code\n$_shareUrl',
                  'I\'m using MirrorSpeed — fast & stable. Join me! Invite code $_code\n$_shareUrl',
                );
                Share.share(msg, subject: tr('MirrorSpeed 邀请', 'MirrorSpeed invite'));
              },
            ),
          ]),
        ),

        // 说明文字
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(
            tr('好友首次付款后，你将获得对应时长：1个月→3天 · 1季度→10天 · 1年→30天',
               'When a friend first pays, you get bonus time: 1 mo → 3 d · 1 qtr → 10 d · 1 yr → 30 d'),
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
        ),

        // 已绑定 / 去绑定邀请码
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: _referredBy != null
              ? Row(children: [
                  Icon(Icons.check_circle_rounded,
                    size: 14, color: kSuccess.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text(tr('已绑定邀请码：$_referredBy', 'Referred by: $_referredBy'),
                    style: TextStyle(color: Colors.white.withOpacity(0.4),
                      fontSize: 12)),
                ])
              : GestureDetector(
                  onTap: onApplyCode,
                  child: Row(children: [
                    Icon(Icons.link_rounded,
                      size: 14, color: Colors.white.withOpacity(0.4)),
                    const SizedBox(width: 6),
                    Text(tr('输入他人邀请码', 'Enter a referral code'),
                      style: TextStyle(
                        color:          Colors.white.withOpacity(0.45),
                        fontSize:       12,
                        decoration:     TextDecoration.underline,
                        decorationColor: Colors.white.withOpacity(0.3),
                      )),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final bool   accent;
  const _StatChip({required this.label, required this.value,
    this.accent = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color:        Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
        style: TextStyle(
          color: Colors.white.withOpacity(0.45), fontSize: 10)),
      const SizedBox(height: 2),
      Text(value,
        style: TextStyle(
          color:      accent ? kSuccess : Colors.white,
          fontSize:   13,
          fontWeight: FontWeight.w600,
        )),
    ]),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData     icon;
  final String       tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tooltip,
    required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding:    const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: Colors.white.withOpacity(0.7)),
      ),
    ),
  );
}

// ── 邀请卡片加载骨架 ──────────────────────────────────────────
class _InviteCardSkeleton extends StatelessWidget {
  const _InviteCardSkeleton();

  @override
  Widget build(BuildContext context) => Container(
    height: 140,
    decoration: BoxDecoration(
      color:        kCard,
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Center(
      child: SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
