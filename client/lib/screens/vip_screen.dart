import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../theme.dart';
import '../utils/portal_link.dart';
import 'sub_page.dart';
import '../widgets/ms_top_controls.dart';

class VipScreen extends StatefulWidget {
  const VipScreen({super.key});
  @override State<VipScreen> createState() => _VipScreenState();
}

// 套餐定义：官网价(cny 人民币总额 / usd 美元总额) + 周期(月数)。
class _Plan {
  final String key, nameZh, nameEn;
  final int    months;
  final int    cny;      // 官网人民币总额
  final double usd;      // 官网美元总额
  final bool   best;
  const _Plan(this.key, this.nameZh, this.nameEn, this.months, this.cny, this.usd, {this.best = false});

  String get name => Brand.isZh ? nameZh : nameEn;
  // 应用内购价 = 官网美元价 × 1.2 后向下取整（整数美元）。
  int get iapUsd => (usd * 1.2).floor();
  String cnyPerMonth() => '¥${(cny / months).round()}';
  String usdIapPerMonth() => '\$${(iapUsd / months).toStringAsFixed(2)}';
}

const List<_Plan> _kPlans = [
  _Plan('monthly',   '月付',   'Monthly',   1,  24,  3.00),
  _Plan('quarterly', '季付',   'Quarterly', 3,  39,  5.00),
  _Plan('halfyear',  '半年',   'Half-Year', 6,  66,  9.00),
  _Plan('yearly',    '年付',   'Yearly',    12, 108, 12.00, best: true),
  _Plan('biennial',  '两年',   '2-Year',    24, 192, 21.00),
];

enum _Tab { iap, web, custom }

class _VipScreenState extends State<VipScreen> {
  _Tab   _tab  = _Tab.web;
  String _pick = 'yearly';

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: tr('开通会员', 'Go Premium'),
      trailing: const MsTopControls(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _hero(),
          const SizedBox(height: 18),
          _tabSwitcher(),
          const SizedBox(height: 16),
          if (_tab == _Tab.iap)    ..._iapTab(),
          if (_tab == _Tab.web)    ..._webTab(),
          if (_tab == _Tab.custom) ..._customTab(),
        ]),
      ),
    );
  }

  // ── Hero ────────────────────────────────────────────────────────
  Widget _hero() => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: msNow.goldBannerBg,
      border: Border.all(color: msNow.gold.withOpacity(0.4)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.auto_awesome_rounded, size: 15, color: msNow.gold),
        const SizedBox(width: 6),
        Text(tr('尊享会员', 'PREMIUM'), style: TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: msNow.gold)),
      ]),
      const SizedBox(height: 12),
      Text(tr('解锁全部速度与节点', 'Unlock full speed & all nodes'),
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.2, color: msNow.gold)),
      const SizedBox(height: 8),
      Text(tr('无广告 · 无限时长 · 4 台设备 · 全部高速节点', 'No ads · Unlimited · 4 devices · All premium nodes'),
        style: TextStyle(fontSize: 12, color: msNow.gold.withOpacity(0.85))),
    ]),
  );

  // ── 三档切换 ─────────────────────────────────────────────────────
  Widget _tabSwitcher() {
    Widget seg(_Tab t, String label) {
      final on = _tab == t;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? msNow.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: on ? Colors.black : msNow.textSecondary.withOpacity(0.6))),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: msNow.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: msNow.textSecondary.withOpacity(0.06))),
      child: Row(children: [
        seg(_Tab.iap,    tr('应用内购', 'In-App')),
        seg(_Tab.web,    tr('官网购买', 'Website')),
        seg(_Tab.custom, tr('私人定制', 'Custom')),
      ]),
    );
  }

  // ── Tab 1：应用内购（美元，官网价 ×1.2 向下取整）─────────────────
  List<Widget> _iapTab() => [
    for (final p in _kPlans) ...[
      _planRow(
        p, selected: _pick == p.key, onTap: () => setState(() => _pick = p.key),
        priceBig: '\$${p.iapUsd}', priceSub: '${p.usdIapPerMonth()}/${tr('月','mo')}'),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 6),
    SizedBox(width: double.infinity, child: FilledButton(
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('应用内购买即将开放，敬请期待 🎉', 'In-app purchase coming soon 🎉')),
        backgroundColor: msNow.brand, duration: Duration(seconds: 2))),
      style: FilledButton.styleFrom(backgroundColor: msNow.brand, padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      child: Text(tr('开通会员 · 敬请期待', 'Subscribe · Coming soon'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
    )),
    const SizedBox(height: 8),
    Center(child: Text(tr('通过 App Store / Google Play 计费', 'Billed via App Store / Google Play'),
      style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.4)))),
  ];

  // ── Tab 2：官网购买（人民币，选中后微信/支付宝直付）──────────────
  List<Widget> _webTab() => [
    for (final p in _kPlans) ...[
      _planRow(
        p, selected: _pick == p.key, onTap: () => setState(() => _pick = p.key),
        priceBig: '¥${p.cny}', priceSub: '${p.cnyPerMonth()}/${tr('月','mo')}'),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 6),
    // 支付宝（推荐）
    _payButton(
      label: tr('支付宝支付', 'Alipay'), color: const Color(0xFF1677ff), recommend: true,
      onTap: () => _payWeb('alipay')),
    const SizedBox(height: 10),
    // 微信
    _payButton(
      label: tr('微信支付', 'WeChat Pay'), color: const Color(0xFF07c160), recommend: false,
      onTap: () => _payWeb('wechat_pay')),
    const SizedBox(height: 10),
    Center(child: Text(tr('金额与官网一致 · 复用登录，无需重复登录', 'Same as website · uses your login'),
      style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.4)))),
  ];

  // 复用 App 登录态跳转官网完成人民币支付（openPortal 走 /auth/app-bridge 免重复登录）。
  void _payWeb(String method) {
    openPortal('/dashboard/billing?plan=$_pick&method=$method&autopay=1');
  }

  // ── Tab 3：私人定制 ──────────────────────────────────────────────
  static const String _kSupportUrl = 'https://www.mirrorspeed.com/support';
  void _openSupport() => launchUrl(Uri.parse(_kSupportUrl), mode: LaunchMode.externalApplication);

  List<Widget> _customTab() => [
    _customCard(Icons.data_usage_rounded, tr('流量套餐', 'Data plan'),
      tr('按流量计费，适合轻量使用', 'Pay-as-you-go data'), tr('¥120 起', 'from ¥120'),
      onTap: _openSupport),
    const SizedBox(height: 10),
    _customCard(Icons.speed_rounded, tr('普通带宽', 'Standard bandwidth'),
      tr('共享高速带宽，性价比之选', 'Shared high-speed bandwidth'), tr('¥400 起', 'from ¥400'),
      onTap: _openSupport),
    const SizedBox(height: 10),
    _customCard(Icons.rocket_launch_rounded, tr('专线带宽', 'Dedicated line'),
      tr('独享专线，稳定低延迟', 'Dedicated line, low latency'), tr('¥1200 起', 'from ¥1200'),
      onTap: _openSupport),
    const SizedBox(height: 10),
    _customCard(Icons.support_agent_rounded, tr('其他定制', 'Other'),
      tr('有特殊需求？联系我们', 'Custom needs? Contact us'), tr('联系客服', 'Contact'),
      onTap: _openSupport),
    const SizedBox(height: 12),
    Center(child: Text(tr('定制方案由客服1对1对接', 'Custom plans handled 1:1 by support'),
      style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.4)))),
  ];

  // ── 通用套餐行（可选中）──────────────────────────────────────────
  Widget _planRow(_Plan p, {required bool selected, required VoidCallback onTap,
      required String priceBig, required String priceSub}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? msNow.brand.withOpacity(0.12) : msNow.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? msNow.brand : msNow.textSecondary.withOpacity(0.06), width: selected ? 1.5 : 1)),
        child: Row(children: [
          Container(width: 20, height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: selected ? msNow.brand : msNow.textSecondary.withOpacity(0.25), width: 2),
              color: selected ? msNow.brand : Colors.transparent),
            child: selected ? const Icon(Icons.check, size: 12, color: Colors.black) : null),
          const SizedBox(width: 14),
          Expanded(child: Row(children: [
            Text(p.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            if (p.best) ...[
              const SizedBox(width: 8),
              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: msNow.gold.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text(tr('最划算', 'BEST'), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: msNow.gold))),
            ],
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(priceBig, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            Text(priceSub, style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.45))),
          ]),
        ]),
      ),
    );
  }

  // 支付按钮（支付宝带「推荐」角标）
  Widget _payButton({required String label, required Color color, required bool recommend, required VoidCallback onTap}) {
    return SizedBox(width: double.infinity, child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: msNow.textPrimary)),
        if (recommend) ...[
          const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: msNow.textSecondary.withOpacity(0.25), borderRadius: BorderRadius.circular(20)),
            child: Text(tr('推荐', 'Best'), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: msNow.textPrimary))),
        ],
      ]),
    ));
  }

  Widget _customCard(IconData icon, String title, String desc, String price, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: msNow.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: msNow.textSecondary.withOpacity(0.06))),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: msNow.brand.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: msNow.brand)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 11, color: msNow.textSecondary.withOpacity(0.45))),
          ])),
          Text(price, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: msNow.brand)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: msNow.textSecondary.withOpacity(0.3)),
        ]),
      ),
    );
  }
}
