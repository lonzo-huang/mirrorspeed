import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../theme.dart';
import '../version.dart';
import 'sub_page.dart';
import 'singbox_test_screen.dart';

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
            _row('DNS', tr('智能 DNS', 'Smart DNS'), locked: true),
            _row('IPv6', tr('已保护', 'Protected'), locked: true),
          ]),
          _group(tr('安全', 'Security'), [
            _row(tr('断网保护', 'Kill switch'), 'ON', locked: true, hint: tr('断线时阻断流量，防止泄露', 'Blocks traffic if VPN drops')),
            _row(tr('加密', 'Encryption'), 'ChaCha20', locked: true),
            _row(tr('流量混淆', 'Obfuscation'), tr('已开启', 'Enabled'), locked: true),
          ]),
          _group(tr('通用', 'General'), [
            _row(tr('语言', 'Language'), tr('跟随系统', 'System'), locked: true),
            _link(context, tr('使用帮助', 'Help'), onTap: () => context.push('/help')),
            _link(context, tr('隐私政策', 'Privacy Policy'), onTap: () => _open('https://www.mirrorspeed.com/privacy')),
            _link(context, tr('服务条款', 'Terms'), onTap: () => _open('https://www.mirrorspeed.com/terms')),
            _link(context, '🧪 sing-box 测试', onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SingboxTestScreen()))),
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
      Text(title.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4))),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Column(children: rows),
      ),
    ]),
  );

  Widget _row(String label, String value, {bool locked = false, String? hint}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04)))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 2),
          child: Text(hint, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)))),
      ])),
      Text(value, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
      if (locked) Padding(padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.lock_outline_rounded, size: 14, color: Colors.white.withOpacity(0.3))),
    ]),
  );

  Widget _link(BuildContext context, String label, {required VoidCallback onTap}) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04)))),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white.withOpacity(0.35)),
      ]),
    ),
  );
}
