import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/vpn_provider.dart';
import '../theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth  = context.watch<AuthProvider>();
    final vpn   = context.watch<VpnProvider>();
    final user  = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '—';

    final isPaid      = auth.dailyQuotaBytes == null;
    final expiryLabel = _buildExpiryLabel(auth);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('个人中心',
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
                _InfoRow(icon: Icons.email_outlined, label: '邮箱', value: email),
                _InfoRow(
                  icon: isPaid
                      ? Icons.workspace_premium_rounded
                      : Icons.person_outline_rounded,
                  label:  '账号类型',
                  value:  isPaid ? '付费会员' : '免费用户',
                  valueColor: isPaid ? kBrand : Colors.white54,
                ),
                if (expiryLabel != null)
                  _InfoRow(
                    icon:  Icons.access_time_rounded,
                    label: '到期时间',
                    value: expiryLabel,
                  ),
                _InfoRow(
                  icon:  Icons.devices_rounded,
                  label: '当前设备',
                  value: auth.deviceLabel ?? '—',
                ),
              ]),

              const SizedBox(height: 16),

              // ── 流量/时长信息（免费用户）───────────────────
              if (!isPaid && auth.dailyQuotaBytes != null) ...[
                _QuotaSection(auth: auth),
                const SizedBox(height: 16),
              ],

              // ── 升级按钮（免费用户）─────────────────────────
              if (!isPaid)
                _UpgradeCard(),

              const SizedBox(height: 16),

              // ── 功能列表 ────────────────────────────────────
              _InfoCard(children: [
                _ActionRow(
                  icon:  Icons.refresh_rounded,
                  label: '刷新配置',
                  onTap: () => auth.refreshConfigs(),
                ),
                _ActionRow(
                  icon:  Icons.open_in_new_rounded,
                  label: '管理订阅',
                  onTap: () => launchUrl(
                    Uri.parse('https://mirrorspeed.com/dashboard'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                _ActionRow(
                  icon:  Icons.help_outline_rounded,
                  label: '使用帮助',
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
                  label: const Text('退出登录',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ),

              const SizedBox(height: 24),

              // ── 版本号 ──────────────────────────────────────
              Text('MirrorSpeed VPN  v1.0.14',
                style: TextStyle(color: Colors.white.withOpacity(0.25),
                  fontSize: 12)),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String? _buildExpiryLabel(AuthProvider auth) {
    // 目前 DeviceInfo 不直接暴露到期时间；付费用户 dailyQuotaBytes == null
    // 后续 API 如果返回 expires_at 可以在这里展示
    return null;
  }

  Future<bool> _confirmLogout(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:  kCard,
        shape:            RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
        title:            const Text('退出登录'),
        content:          const Text('确定要退出当前账号吗？',
                            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
              style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('退出', style: TextStyle(color: kDanger)),
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
                isPaid ? '✦ 付费会员' : '免费用户',
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

// ── 流量进度条（免费用户）─────────────────────────────────────
class _QuotaSection extends StatelessWidget {
  final AuthProvider auth;
  const _QuotaSection({required this.auth});

  String _fmt(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final used     = auth.dailyBytesUsed;
    final quota    = auth.dailyQuotaBytes!;
    final ratio    = (used / quota).clamp(0.0, 1.0);
    final color    = auth.isSuspended
        ? kDanger : ratio > 0.8 ? Colors.amber : kSuccess;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:         color.withOpacity(0.08),
        borderRadius:  BorderRadius.circular(16),
        border:        Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.data_usage_rounded, size: 15, color: color),
          const SizedBox(width: 6),
          Text('今日免费流量',
            style: TextStyle(color: color, fontSize: 13,
              fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(auth.isSuspended
            ? '已用完'
            : '${_fmt(used)} / ${_fmt(quota)}',
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
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('升级付费会员',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          SizedBox(height: 3),
          Text('无限流量 · 全节点 · 无广告',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
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
        child: const Text('升级', style: TextStyle(fontSize: 13)),
      ),
    ]),
  );
}
