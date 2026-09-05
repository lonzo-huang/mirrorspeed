import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../brand.dart';
import '../theme.dart';

/// 邀请好友独立子页面（从「设置」进入）。放子页避免进「我的」每次重拉邀请状态拖慢。
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.fetchReferralInfo();
  }

  void _refresh() => setState(() {
    _future = ApiService.instance.fetchReferralInfo();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: msNow.bg,
      appBar: AppBar(
        title: Text(tr('邀请好友', 'Invite friends')),
        backgroundColor: msNow.bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _InviteCardSkeleton();
            }
            if (snap.hasError || !snap.hasData) {
              return Center(child: Text(tr('加载失败，下拉重试', 'Failed to load'),
                  style: TextStyle(color: msNow.textMuted)));
            }
            return _InviteCard(
              data:        snap.data!,
              onApplyCode: () => _showApplyCodeDialog(context),
              onRefresh:   _refresh,
            );
          },
        ),
      ),
    );
  }

  Future<void> _showApplyCodeDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: msNow.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('输入邀请码', 'Enter referral code')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: tr('例如：MX7K9P', 'e.g. MX7K9P'),
            hintStyle: TextStyle(color: msNow.textMuted),
          ),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消', 'Cancel'), style: TextStyle(color: msNow.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              final code = ctrl.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ApiService.instance.applyReferralCode(code);
                _refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('邀请码绑定成功 🎉', 'Referral code applied 🎉')),
                    backgroundColor: kSuccess));
                }
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(e.message), backgroundColor: kDanger));
                }
              }
            },
            child: Text(tr('绑定', 'Apply')),
          ),
        ],
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onApplyCode;
  final VoidCallback onRefresh;
  const _InviteCard({required this.data, required this.onApplyCode, required this.onRefresh});

  String get _code        => data['referral_code']   as String? ?? '—';
  String get _shareUrl    => data['share_url']        as String? ?? '';
  int    get _inviteCount => data['invite_count']     as int?    ?? 0;
  int    get _bonusDays   => data['total_bonus_days'] as int?    ?? 0;
  String? get _expiresAt  => data['bonus_expires_at'] as String?;
  String? get _referredBy => data['referred_by_code'] as String?;

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
          colors: [const Color(0xFF7C3AED).withOpacity(0.18), const Color(0xFF2563EB).withOpacity(0.12)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            const Icon(Icons.card_giftcard_rounded, color: Color(0xFFA78BFA), size: 18),
            const SizedBox(width: 8),
            Text(tr('邀请好友', 'Invite friends'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA))),
            const Spacer(),
            GestureDetector(onTap: onRefresh,
              child: Icon(Icons.refresh_rounded, color: msNow.textSecondary.withOpacity(0.35), size: 18)),
          ]),
        ),
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
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('你的邀请码', 'Your invite code'),
                style: TextStyle(color: msNow.textSecondary.withOpacity(0.5), fontSize: 11)),
              const SizedBox(height: 4),
              Text(_code, style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 6,
                color: Color(0xFFE2E8F0), fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const Spacer(),
            _IconBtn(icon: Icons.copy_rounded, tooltip: tr('复制邀请码', 'Copy code'), onTap: () {
              Clipboard.setData(ClipboardData(text: _code));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr('邀请码已复制', 'Code copied')), duration: const Duration(seconds: 1)));
            }),
            const SizedBox(width: 8),
            _IconBtn(icon: Icons.share_rounded, tooltip: tr('分享', 'Share'), onTap: () {
              if (_shareUrl.isEmpty) return;
              final msg = tr('我在用 MirrorSpeed，高速又稳定，一起来用吧！邀请码 $_code\n$_shareUrl',
                'I\'m using MirrorSpeed — fast & stable. Join me! Invite code $_code\n$_shareUrl');
              Share.share(msg, subject: tr('MirrorSpeed 邀请', 'MirrorSpeed invite'));
            }),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Text(
            tr('好友首次付款后，你将获得对应时长：1个月→3天 · 1季度→10天 · 1年→30天',
               'When a friend first pays, you get bonus time: 1 mo → 3 d · 1 qtr → 10 d · 1 yr → 30 d'),
            style: TextStyle(color: msNow.textSecondary.withOpacity(0.4), fontSize: 11)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: _referredBy != null
              ? Row(children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: kSuccess.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text(tr('已绑定邀请码：$_referredBy', 'Referred by: $_referredBy'),
                    style: TextStyle(color: msNow.textSecondary.withOpacity(0.4), fontSize: 12)),
                ])
              : GestureDetector(onTap: onApplyCode, child: Row(children: [
                  Icon(Icons.link_rounded, size: 14, color: msNow.textSecondary.withOpacity(0.4)),
                  const SizedBox(width: 6),
                  Text(tr('输入他人邀请码', 'Enter a referral code'),
                    style: TextStyle(color: msNow.textSecondary.withOpacity(0.45), fontSize: 12,
                      decoration: TextDecoration.underline, decorationColor: msNow.textSecondary.withOpacity(0.3))),
                ])),
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final bool accent;
  const _StatChip({required this.label, required this.value, this.accent = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: msNow.textSecondary.withOpacity(0.07), borderRadius: BorderRadius.circular(8)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: msNow.textSecondary.withOpacity(0.45), fontSize: 10)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: accent ? kSuccess : msNow.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: msNow.textSecondary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 18, color: msNow.textSecondary.withOpacity(0.7)),
    ),
  ));
}

class _InviteCardSkeleton extends StatelessWidget {
  const _InviteCardSkeleton();
  @override
  Widget build(BuildContext context) => Container(
    height: 140,
    decoration: BoxDecoration(color: msNow.card, borderRadius: BorderRadius.circular(16)),
    child: const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
  );
}
