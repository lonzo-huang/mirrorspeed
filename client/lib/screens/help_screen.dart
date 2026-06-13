import 'package:flutter/material.dart';
import '../brand.dart';
import '../theme.dart';
import 'sub_page.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  List<List<String>> get _faq => [
    [tr('如何连接？', 'How do I connect?'),
     tr('点主页中间的大按钮即可。默认「智能选择」会自动接入延迟最低、最空闲的节点。',
        'Tap the big button on the home screen. "Auto" picks the fastest, least-busy node.')],
    [tr('如何选择指定节点？', 'How do I choose a node?'),
     tr('点节点卡片进入列表，每个节点显示延迟和负载，点任意节点切换，选择会被记住。',
        'Open the node list; each shows latency and load. Tap one to switch; your choice is remembered.')],
    [tr('免费时长是什么？', 'What is the free trial?'),
     tr('免费用户每天有连接时长额度，每天重置；用完会自动断开，可看广告或开通会员延长。',
        'Free users get daily connection time that resets each day. Watch ads or go premium for more.')],
    [tr('如何看广告延长时长？', 'How to extend with ads?'),
     tr('时长用完后点「看广告解锁」，连续看满约 50 秒即获得额外免费时长。',
        'Tap "Watch ads"; after about 50s of viewing you get extra free minutes.')],
    [tr('智能模式与全局模式', 'Smart vs Global'),
     tr('智能模式中国大陆流量直连、境外走 VPN，速度最佳；全局模式全部走 VPN。',
        'Smart keeps mainland-China traffic direct and routes overseas via VPN. Global routes everything.')],
    [tr('连上了但打不开网页', 'Connected but no internet'),
     tr('先断开重连，或换一个节点；若节点显示「超时」请换其他节点。',
        'Reconnect or switch nodes; if a node shows "timeout", pick another.')],
    [tr('联系客服', 'Contact support'),
     tr('发邮件到 mirrorspeed@mirrorquant.com，我们会尽快协助。',
        'Email mirrorspeed@mirrorquant.com and we will help as soon as possible.')],
  ];

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: tr('使用帮助', 'Help & FAQ'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final item in _faq) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item[0], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(item[1], style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.white.withOpacity(0.6))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
