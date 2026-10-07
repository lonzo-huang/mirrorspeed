import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../theme.dart';
import '../version.dart';
import 'sub_page.dart';
import 'invite_screen.dart';
import 'app_proxy_screen.dart';
import '../services/app_proxy_store.dart';
import '../utils/dns_region.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: tr('加速设置', 'Settings'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: Column(children: [
          _group(tr('协议', 'Protocol'), [
            _row(tr('协议', 'Protocol'), 'MirrorTunnel V1.0', locked: true),
            const DnsRegionRow(),
            _row('IPv6', tr('已保护', 'Protected'), locked: true),
          ]),
          _group(tr('安全', 'Security'), [
            _row(tr('断网保护', 'Kill switch'), 'ON', locked: true, hint: tr('断线时阻断流量，防止泄露', 'Blocks traffic if VPN drops')),
            _row(tr('加密', 'Encryption'), 'ChaCha20', locked: true),
            _row(tr('流量混淆', 'Obfuscation'), tr('已开启', 'Enabled'), locked: true),
          ]),
          if (AppProxyStore.supported)
            _group(tr('智能模式', 'Smart mode'), [
              _link(context, tr('分应用代理', 'Per-app proxy'),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppProxyScreen()))),
            ]),
          _group(tr('通用', 'General'), [
            _link(context, tr('邀请好友', 'Invite friends'), onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InviteScreen()))),
            _row(tr('语言', 'Language'), tr('跟随系统', 'System'), locked: true),
            _link(context, tr('使用帮助', 'Help'), onTap: () => context.push('/help')),
            _link(context, tr('隐私政策', 'Privacy Policy'), onTap: () => _open('https://www.mirrorspeed.com/privacy')),
            _link(context, tr('服务条款', 'Terms'), onTap: () => _open('https://www.mirrorspeed.com/terms')),
            _row(tr('版本', 'Version'), 'v$kAppVersion'),
          ]),
        ]),
      ),
    );
  }

  static void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Widget _group(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w600, color: msNow.textSecondary.withOpacity(0.4))),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: msNow.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: msNow.textSecondary.withOpacity(0.05))),
        child: Column(children: rows),
      ),
    ]),
  );

  Widget _row(String label, String value, {bool locked = false, String? hint}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: msNow.textSecondary.withOpacity(0.04)))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 2),
          child: Text(hint, style: TextStyle(fontSize: 11, color: msNow.textSecondary.withOpacity(0.4)))),
      ])),
      Text(value, style: TextStyle(fontSize: 12, color: msNow.textSecondary.withOpacity(0.5))),
      if (locked) Padding(padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.lock_outline_rounded, size: 14, color: msNow.textSecondary.withOpacity(0.3))),
    ]),
  );

  Widget _link(BuildContext context, String label, {required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: msNow.textSecondary.withOpacity(0.04)))),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Icon(Icons.chevron_right_rounded, size: 18, color: msNow.textSecondary.withOpacity(0.35)),
      ]),
    ),
  );
}

/// DNS 方案选择行：自动 / 中国大陆 / 海外。点开底部选择,存 DnsRegionStore。
class DnsRegionRow extends StatefulWidget {
  const DnsRegionRow({super.key});
  @override
  State<DnsRegionRow> createState() => _DnsRegionRowState();
}

class _DnsRegionRowState extends State<DnsRegionRow> {
  DnsRegion _r = DnsRegion.auto;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final r = await DnsRegionStore.load();
    if (mounted) setState(() => _r = r);
  }

  String _label(DnsRegion r) {
    switch (r) {
      case DnsRegion.auto:     return tr('自动', 'Auto');
      case DnsRegion.china:    return tr('中国大陆', 'China');
      case DnsRegion.overseas: return tr('海外', 'Overseas');
    }
  }
  String _desc(DnsRegion r) {
    switch (r) {
      case DnsRegion.auto:     return tr('按当前网络环境自动选择', 'Auto by network');
      case DnsRegion.china:    return tr('国内直连 + 防污染分流', 'CN direct + anti-pollution');
      case DnsRegion.overseas: return tr('全部经节点，不做国内分流', 'All via node');
    }
  }

  Future<void> _choose() async {
    final sel = await showModalBottomSheet<DnsRegion>(
      context: context,
      backgroundColor: msNow.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(alignment: Alignment.centerLeft,
            child: Text(tr('DNS 方案', 'DNS scheme'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        for (final r in DnsRegion.values)
          ListTile(
            title: Text(_label(r)),
            subtitle: Text(_desc(r), style: const TextStyle(fontSize: 11)),
            trailing: _r == r ? Icon(Icons.check_rounded, color: msNow.accentOn) : null,
            onTap: () => Navigator.pop(ctx, r),
          ),
        const SizedBox(height: 8),
      ])),
    );
    if (sel != null) {
      await DnsRegionStore.save(sel);
      if (mounted) setState(() => _r = sel);
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: _choose,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: msNow.textSecondary.withOpacity(0.04)))),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('DNS 方案', 'DNS scheme'), style: const TextStyle(fontSize: 14)),
          Padding(padding: const EdgeInsets.only(top: 2),
            child: Text(_desc(_r), style: TextStyle(fontSize: 11, color: msNow.textSecondary.withOpacity(0.4)))),
        ])),
        Text(_label(_r), style: TextStyle(fontSize: 12, color: msNow.textSecondary.withOpacity(0.5))),
        Icon(Icons.chevron_right_rounded, size: 18, color: msNow.textSecondary.withOpacity(0.35)),
      ]),
    ),
  );
}
