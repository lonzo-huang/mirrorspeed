import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

/// 应用内订阅（iOS = App Store / Android = Google Play）。
///
/// 流程：queryProducts 拉取商品与本地化价格 → buy() 发起购买（把用户 UUID 作为
/// applicationUserName 传给商店：iOS=appAccountToken / Android=obfuscatedAccountId，
/// 续费/退款通知才能对上用户）→ 购买流回调里交给后端核验并开通会员：
///   iOS   → /api/iap/apple/verify（JWS / transactionId）
///   Android → /api/iap/google/verify（purchaseToken + productId）
/// 核验成功后才 completePurchase（Android 的 completePurchase 会 acknowledge，
/// 必须在 3 天内，否则 Google 自动退款）。核验失败不 complete：商店下次启动重投递，
/// 避免"扣了钱没开通"。
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  /// 档位 → 各平台商品 ID（单一事实来源）。Apple 与 Google 在各自后台建的 ID 不一致：
  ///   iOS  = App Store Connect 的 ID（vip_*）
  ///   Android = Google Play Console 的 ID（mirrorspeed.vpn.premium.*，注意半年=semiannual）
  /// biennial(两年)不走内购。DB plans.{apple,google}_product_id 必须与此一致。
  static const _tierIds = <String, (String apple, String google)>{
    'monthly':   ('vip_monthly',   'mirrorspeed.vpn.premium.monthly'),
    'quarterly': ('vip_quarterly', 'mirrorspeed.vpn.premium.quarterly'),
    'halfyear':  ('vip_halfyear',  'mirrorspeed.vpn.premium.semiannual'),
    'yearly':    ('vip_yearly',    'mirrorspeed.vpn.premium.yearly'),
  };

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 把档位(monthly/quarterly/halfyear/yearly)映射到当前平台的商品 ID；未知档位返回 null。
  static String? storeProductId(String tier) {
    final e = _tierIds[tier];
    return e == null ? null : (_isAndroid ? e.$2 : e.$1);
  }

  /// 当前平台要向商店查询的全部商品 ID。
  static Set<String> get productIds =>
      _tierIds.values.map((e) => _isAndroid ? e.$2 : e.$1).toSet();

  /// macOS 也走同一套 StoreKit：Mac App Store 对数字会员要求必须提供内购，
  /// 不能只给官网支付入口。插件(in_app_purchase_storekit)的 darwin 实现 iOS/macOS
  /// 共用，商品 ID 与订阅群组也共用（storeProductId 对非安卓一律取 Apple 侧 ID），
  /// 无需为 macOS 单独建产品。
  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// 购买/恢复结果事件，UI 据此提示并刷新会员状态。
  final _events = StreamController<IapEvent>.broadcast();
  Stream<IapEvent> get events => _events.stream;

  /// 应用启动时调用一次：尽早监听购买流，接住上次未完成的交易。
  void init() {
    if (!supported || _sub != null) return;
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      _events.add(IapEvent.error('$e'));
    });
  }

  /// 最近一次商品查询的诊断信息（显示在「我的 → 错误信息」里，仅 Apple 平台）。
  /// TestFlight 包看不到控制台日志，排查「某个套餐不显示」全靠它：
  /// 是 App Store 说「没这个商品」(notFound)，还是请求本身报错(error)。
  String? lastQueryReport;

  Future<List<ProductDetails>> queryProducts() async {
    if (!supported) return [];
    final t = DateTime.now().toIso8601String().substring(11, 19);
    if (!await _iap.isAvailable()) {
      lastQueryReport = '[$t] App Store 不可用(isAvailable=false)';
      return [];
    }
    try {
      final res = await _iap.queryProductDetails(productIds);
      final found = res.productDetails.map((d) => '${d.id}=${d.price}').join(', ');
      lastQueryReport = '[$t] 找到: ${found.isEmpty ? '无' : found}'
          '${res.notFoundIDs.isEmpty ? '' : '\n未找到: ${res.notFoundIDs.join(', ')}'}'
          '${res.error == null ? '' : '\n错误: ${res.error!.code} ${res.error!.message}'}';
      if (kDebugMode && res.notFoundIDs.isNotEmpty) debugPrint('IAP 未找到商品: ${res.notFoundIDs}');
      return res.productDetails;
    } catch (e) {
      lastQueryReport = '[$t] 查询异常: $e';
      rethrow;
    }
  }

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> buy(ProductDetails product) async {
    final uid = _userId;
    if (uid == null) { _events.add(IapEvent.error('请先登录')); return; }
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product, applicationUserName: uid));
  }

  Future<void> restore() async {
    if (!supported) return;
    await _iap.restorePurchases(applicationUserName: _userId);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const IapEvent(IapEventType.pending));
        case PurchaseStatus.canceled:
          _events.add(const IapEvent(IapEventType.canceled));
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.error:
          _events.add(IapEvent.error(p.error?.message ?? '购买失败'));
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndComplete(p);
      }
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails p) async {
    if (_userId == null) return;   // 未登录不核验、不 complete，登录后重投递
    try {
      // macOS 与 iOS 同为 App Store 交易，核验走同一个接口（JWS 签名交易）。
      // 漏掉 macOS 会导致「扣了钱但不开通会员」。
      if (Platform.isIOS || Platform.isMacOS) {
        final jws = p.verificationData.serverVerificationData;
        await ApiService.instance.verifyApplePurchase(
          transactionId: p.purchaseID,
          signedTransaction: jws.split('.').length == 3 ? jws : null,
        );
      } else if (Platform.isAndroid) {
        // Android：serverVerificationData = Google Play purchaseToken。
        await ApiService.instance.verifyGooglePurchase(
          purchaseToken: p.verificationData.serverVerificationData,
          productId: p.productID,
        );
      } else {
        return;
      }
      // 核验成功后才 complete（Android 借此 acknowledge；未 ack 的购买 Google 会在 3 天后退款）。
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      _events.add(IapEvent(p.status == PurchaseStatus.restored ? IapEventType.restored : IapEventType.purchased));
    } catch (e) {
      _events.add(IapEvent.error('验证购买失败：$e'));
    }
  }
}

enum IapEventType { pending, purchased, restored, canceled, error }

class IapEvent {
  final IapEventType type;
  final String? message;
  const IapEvent(this.type, [this.message]);
  factory IapEvent.error(String m) => IapEvent(IapEventType.error, m);
}
