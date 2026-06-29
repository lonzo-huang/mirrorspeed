import 'package:flutter/material.dart';
import '../brand.dart';
import '../theme.dart';
import 'sub_page.dart';

class VipScreen extends StatefulWidget {
  const VipScreen({super.key});
  @override State<VipScreen> createState() => _VipScreenState();
}

class _Plan {
  final String id, name, per, price, sub;
  final bool best;
  const _Plan(this.id, this.name, this.per, this.price, this.sub, {this.best = false});
}

class _VipScreenState extends State<VipScreen> {
  String _pick = 'yearly';

  // 与官网套餐/价格保持一致（CN：¥；EN：$）。
  // monthly ¥24 · quarterly ¥36 · yearly ¥96 · biennial ¥168
  List<_Plan> get _plans => [
    _Plan('monthly',   tr('月付', 'Monthly'),    tr('/月',  '/mo'),  tr('¥24',  '\$3'),     tr('灵活', 'Flexible')),
    _Plan('quarterly', tr('季付', 'Quarterly'),  tr('/季',  '/qtr'), tr('¥36',  '\$4.50'),  tr('省 50%', 'Save 50%')),
    _Plan('yearly',    tr('年付', 'Yearly'),     tr('/年',  '/yr'),  tr('¥96',  '\$12'),    tr('省 67%', 'Save 67%'), best: true),
    _Plan('biennial',  tr('两年', '2-Year'),     tr('/2年', '/2yr'), tr('¥168', '\$21.60'), tr('省 71%', 'Save 71%')),
  ];

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: tr('开通会员', 'Go Premium'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1530), Color(0xFF0F0B22)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, size: 15, color: kGold),
                const SizedBox(width: 6),
                Text(tr('尊享会员', 'PREMIUM'), style: const TextStyle(fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w700, color: kGold)),
              ]),
              const SizedBox(height: 14),
              Text(tr('解锁全部速度与节点', 'Unlock full speed & all nodes'),
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, height: 1.2)),
              const SizedBox(height: 8),
              Text(tr('无广告 · 无限时长 · 全部高速节点', 'No ads · Unlimited time · All premium nodes'),
                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
              const SizedBox(height: 14),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in [tr('无广告', 'No ads'), tr('多设备', 'Multi-device'), tr('无限速', 'Unlimited'), tr('零日志', 'No-logs')])
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: Text(tag, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          // Plans（4 个套餐：2×2 网格，避免一行挤）
          for (int r = 0; r < _plans.length; r += 2) ...[
            Row(children: [
              for (int c = r; c < r + 2 && c < _plans.length; c++) ...[
                Expanded(child: _PlanCard(plan: _plans[c], selected: _pick == _plans[c].id,
                  onTap: () => setState(() => _pick = _plans[c].id))),
                if (c == r) const SizedBox(width: 10),
              ],
            ]),
            if (r + 2 < _plans.length) const SizedBox(height: 10),
          ],
          const SizedBox(height: 20),

          // Perks
          Text(tr('会员权益', 'Member benefits').toUpperCase(),
            style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4))),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.05))),
            child: Column(children: [
              _perk(Icons.all_inclusive_rounded, tr('无限时长', 'Unlimited time'), tr('不限免费额度，随心连接', 'No daily free-time limit')),
              _perk(Icons.bolt_rounded, tr('极速节点', 'Premium speed'), tr('优先接入高带宽节点', 'Priority high-bandwidth nodes')),
              _perk(Icons.shield_rounded, tr('强加密', 'Strong encryption'), tr('自研加速引擎，极速安全', 'Proprietary speed engine, fast & secure')),
              _perk(Icons.devices_rounded, tr('多设备', 'Multi-device'), tr('多台设备同时在线', 'Use on multiple devices')),
              _perk(Icons.block_rounded, tr('无广告', 'Ad-free'), tr('彻底去除所有广告', 'Removes all ads'), last: true),
            ]),
          ),
          const SizedBox(height: 24),

          // CTA — IAP 开发中，暂不接外部支付（合规）
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(tr('应用内购买即将开放，敬请期待 🎉', 'In-app purchase coming soon 🎉')),
                  backgroundColor: kBrand, duration: const Duration(seconds: 2)));
              },
              style: FilledButton.styleFrom(
                backgroundColor: kBrand, padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(tr('开通会员 · 敬请期待', 'Subscribe · Coming soon'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text(tr('订阅可随时取消', 'Cancel anytime'),
            style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)))),
        ]),
      ),
    );
  }

  Widget _perk(IconData icon, String t, String s, {bool last = false}) => Container(
    decoration: BoxDecoration(
      border: last ? null : Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(children: [
      Container(width: 36, height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: kBrand.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: kBrand)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        Text(s, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45))),
      ])),
      const Icon(Icons.check_rounded, size: 18, color: kAccentOn),
    ]),
  );
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? kBrand.withOpacity(0.12) : kPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? kBrand : Colors.white.withOpacity(0.06), width: selected ? 1.5 : 1),
        ),
        child: Column(children: [
          if (plan.best)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: kGold.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
              child: Text(tr('最划算', 'BEST'), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: kGold)),
            ),
          Text(plan.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(plan.price, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(plan.per, style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4))),
          const SizedBox(height: 6),
          Text(plan.sub, style: TextStyle(fontSize: 9, color: selected ? kBrand : Colors.white.withOpacity(0.5))),
        ]),
      ),
    );
  }
}
