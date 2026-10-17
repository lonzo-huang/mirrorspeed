import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../brand.dart';
import '../theme.dart';
import '../services/iap_service.dart';
import '../services/free_node_service.dart';
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
  /// 本平台是否有 App Store 内购（iOS + macOS）。
  final bool _appStore = IapService.supported;

  /// Apple 端是否展示「官网购买」入口。
  ///
  /// 仅在「中文界面」或「出口 IP 在中国境内」时展示 —— 国内用户常无法使用 App Store
  /// 支付（无海外支付方式），人民币直付是其唯一可行路径。
  ///
  /// 注意：App Store 审核指南 3.1.1 禁止在 App 内引导外部购买，中国区没有外部购买
  /// 链接豁免。此入口按产品决策保留，风险已知（见本次需求）。
  bool _showWebBuy = false;

  late _Tab _tab = _appStore ? _Tab.iap : _Tab.web;
  String _pick = 'yearly';

  // ── App Store 商品与购买状态（iOS + macOS）──
  List<ProductDetails> _products = [];
  bool _loadingProducts = false;
  bool _busy = false;
  StreamSubscription<IapEvent>? _iapSub;
  Timer? _restoreTimer;

  @override
  void initState() {
    super.initState();
    if (_appStore) {
      _loadProducts();
      _iapSub = IapService.instance.events.listen(_onIapEvent);
    }
    _resolveWebBuyVisibility();
  }

  /// 判定是否展示官网购买入口。中文界面直接展示（无需等网络）；英文界面再看出口 IP
  /// 是否在国内。非 Apple 平台一律展示（行为与以前一致）。
  Future<void> _resolveWebBuyVisibility() async {
    // 非商店平台(如 Windows)无内购 → 一律显示官网购买 + 私人定制。
    if (!_appStore) {
      if (mounted) setState(() => _showWebBuy = true);
      return;
    }
    // 商店平台(iOS/macOS/Android):仅「中文界面」或「出口 IP 在中国境内」时显示官网购买+私人定制；
    // 国际用户只走商店内购(Apple 3.1.1 / Google Play 政策)。显示时默认选中「官网购买」。
    if (Brand.isZh) {
      if (mounted) setState(() { _showWebBuy = true; _tab = _Tab.web; });
      return;
    }
    // 出口判定失败(null)时不展示 —— 宁可少展示，也不要在境外用户面前露出外部支付入口。
    final inCn = await FreeNodeService.instance.egressInChina();
    if (mounted && inCn == true) setState(() { _showWebBuy = true; _tab = _Tab.web; });
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    _restoreTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    final list = await IapService.instance.queryProducts().catchError((_) => <ProductDetails>[]);
    if (!mounted) return;
    setState(() { _products = list; _loadingProducts = false; });
  }

  ProductDetails? _productFor(_Plan p) {
    final id = IapService.storeProductId(p.key);   // 按平台取商品 ID（iOS=vip_* / Android=mirrorspeed.*）
    if (id == null) return null;                    // biennial 等不走内购的档位
    for (final d in _products) { if (d.id == id) return d; }
    return null;
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: msNow.brand, duration: const Duration(seconds: 3)));

  void _onIapEvent(IapEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case IapEventType.pending:
        return;                                  // 仍在处理（如家长批准），保持 busy
      case IapEventType.purchased:
      case IapEventType.restored:
        _restoreTimer?.cancel();
        setState(() => _busy = false);
        _toast(e.type == IapEventType.restored
            ? tr('已恢复会员 🎉', 'Membership restored 🎉')
            : tr('开通成功，欢迎成为会员 🎉', 'Welcome to Premium 🎉'));
      case IapEventType.canceled:
        setState(() => _busy = false);
      case IapEventType.error:
        _restoreTimer?.cancel();
        setState(() => _busy = false);
        _toast(e.message ?? tr('购买失败', 'Purchase failed'));
    }
  }

  Future<void> _buy() async {
    final plan = _kPlans.firstWhere((p) => p.key == _pick);
    final product = _productFor(plan);
    if (product == null) return;
    setState(() => _busy = true);
    try {
      await IapService.instance.buy(product);
    } catch (e) {
      if (mounted) { setState(() => _busy = false); _toast('$e'); }
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    await IapService.instance.restore();
    // 没有可恢复的订阅时 StoreKit 不会回调任何交易，超时提示。
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_busy) return;
      setState(() => _busy = false);
      _toast(tr('未找到可恢复的订阅', 'No subscription to restore'));
    });
  }

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
          // Apple 端且不展示官网入口时：只有 App Store 内购，无需切换器。
          if (_appStore && !_showWebBuy) ..._appStoreTab() else ...[
            _tabSwitcher(),
            const SizedBox(height: 16),
            // Apple 的「应用内购」栏用真实 App Store 商品价；其它平台用官网价 ×1.2。
            if (_tab == _Tab.iap)    ...(_appStore ? _appStoreTab() : _iapTab()),
            if (_tab == _Tab.web)    ..._webTab(),
            if (_tab == _Tab.custom) ..._customTab(),
          ],
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
        if (_showWebBuy) seg(_Tab.web,    tr('官网购买', 'Website')),
        if (_showWebBuy) seg(_Tab.custom, tr('私人定制', 'Custom')),
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

  // ── iOS：App Store 自动续期订阅（价格取 App Store 本地化价格）──────
  static const _kTermsUrl   = 'https://www.mirrorspeed.com/terms';
  static const _kPrivacyUrl = 'https://www.mirrorspeed.com/privacy';

  String _periodText(String key) => switch (key) {
    'monthly'   => tr('每月自动续订', 'per month, auto-renews'),
    'quarterly' => tr('每 3 个月自动续订', 'every 3 months, auto-renews'),
    'halfyear'  => tr('每 6 个月自动续订', 'every 6 months, auto-renews'),
    _           => tr('每年自动续订', 'per year, auto-renews'),
  };

  List<Widget> _appStoreTab() {
    final muted = TextStyle(fontSize: 10.5, height: 1.5, color: msNow.textSecondary.withOpacity(0.5));
    if (_loadingProducts) {
      return [const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))];
    }
    final plans = _kPlans.where((p) => _productFor(p) != null).toList();
    if (plans.isEmpty) {
      return [
        const SizedBox(height: 20),
        Center(child: Text(tr('暂时无法获取订阅商品，请稍后重试', 'Subscriptions unavailable, please retry'),
          style: TextStyle(color: msNow.textSecondary.withOpacity(0.6)))),
        const SizedBox(height: 12),
        Center(child: TextButton(onPressed: _loadProducts, child: Text(tr('重试', 'Retry')))),
      ];
    }
    if (!plans.any((p) => p.key == _pick)) _pick = plans.last.key;

    return [
      for (final p in plans) ...[
        _planRow(p, selected: _pick == p.key, onTap: () => setState(() => _pick = p.key),
          priceBig: _productFor(p)!.price, priceSub: _periodText(p.key)),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _busy ? null : _buy,
        style: FilledButton.styleFrom(backgroundColor: msNow.brand, padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Text(tr('立即订阅', 'Subscribe'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      )),
      const SizedBox(height: 4),
      Center(child: TextButton(onPressed: _busy ? null : _restore,
        child: Text(tr('恢复购买', 'Restore Purchases'), style: TextStyle(fontSize: 13, color: msNow.brand)))),
      const SizedBox(height: 4),
      Text(Platform.isIOS || Platform.isMacOS
        ? tr(
            '订阅费用将在确认购买时从您的 Apple ID 账户扣除。除非在当前订阅期结束前至少 24 小时关闭自动续订，'
            '否则订阅将自动续订并按相同价格扣费。您可以在 App Store 的「账户设置」中管理或取消订阅。',
            'Payment is charged to your Apple ID at confirmation of purchase. The subscription renews automatically '
            'at the same price unless auto-renew is turned off at least 24 hours before the end of the current period. '
            'Manage or cancel in your App Store account settings.')
        : tr(
            '订阅费用将在确认购买时从您的 Google Play 账户扣除。除非在当前订阅期结束前至少 24 小时关闭自动续订，'
            '否则订阅将自动续订并按相同价格扣费。您可以在 Google Play 的「订阅」中管理或取消订阅。',
            'Payment is charged to your Google Play account at confirmation of purchase. The subscription renews '
            'automatically at the same price unless auto-renew is turned off at least 24 hours before the end of the '
            'current period. Manage or cancel in your Google Play subscriptions.'),
        style: muted, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(onPressed: () => launchUrl(Uri.parse(_kTermsUrl), mode: LaunchMode.externalApplication),
          child: Text(tr('使用条款', 'Terms of Use'), style: const TextStyle(fontSize: 11))),
        Text('·', style: muted),
        TextButton(onPressed: () => launchUrl(Uri.parse(_kPrivacyUrl), mode: LaunchMode.externalApplication),
          child: Text(tr('隐私政策', 'Privacy Policy'), style: const TextStyle(fontSize: 11))),
      ]),
    ];
  }

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
  ];

  // 复用 App 登录态跳转官网完成人民币支付（openPortal 走 /auth/app-bridge 免重复登录）。
  void _payWeb(String method) {
    openPortal('/dashboard/billing?plan=$_pick&method=$method&autopay=1');
  }

  // ── Tab 3：私人定制 ──────────────────────────────────────────────
  static const String _kSupportUrl = 'https://www.mirrorspeed.com/support';
  void _openSupport() => launchUrl(Uri.parse(_kSupportUrl), mode: LaunchMode.externalApplication);

  Future<void> _openUrl(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  List<Widget> _customTab() => [
    _customCard(Icons.dns_rounded, tr('共享VPS', 'Shared VPS'),
      tr('多人共享，高性价比入门', 'Shared VPS, best value'), tr('低至 ¥8/月', 'from ¥8/mo'),
      onTap: () => _openUrl('https://poolvip.airlane.cloud/products?kind=vps')),
    const SizedBox(height: 10),
    _customCard(Icons.home_rounded, tr('家宽住宅', 'Residential'),
      tr('真实家庭住宅 IP', 'Real residential IP'), tr('低至 ¥30/月', 'from ¥30/mo'),
      onTap: () => _openUrl('https://poolvip.airlane.cloud/products?kind=proxy')),
    const SizedBox(height: 10),
    _customCard(Icons.rocket_launch_rounded, tr('独享VPS', 'Dedicated VPS'),
      tr('独享资源，稳定低延迟', 'Dedicated VPS, low latency'), tr('低至 ¥50/月', 'from ¥50/mo'),
      onTap: () => _openUrl('https://poolvip.airlane.cloud/products?kind=vps')),
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
