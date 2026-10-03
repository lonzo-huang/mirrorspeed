import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_service.dart';

/// App Store 应用内订阅（目前仅 iOS 启用）。
///
/// 流程：queryProducts 拉取商品与本地化价格 → buy() 发起购买（把用户 UUID 作为
/// appAccountToken 传给苹果，续费/退款通知才能对上用户）→ 购买流回调里交给后端
/// /api/iap/apple/verify 核验并开通会员 → 核验成功后才 completePurchase。
/// 核验失败不 complete：StoreKit 会在下次启动重新投递，避免"扣了钱没开通"。
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  /// App Store Connect 中的订阅商品 ID（苹果自动续期订阅最长 1 年，无两年档）。
  static const productIds = <String>{'vip_monthly', 'vip_quarterly', 'vip_halfyear', 'vip_yearly'};

  static bool get supported => !kIsWeb && Platform.isIOS;

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

  /// 最近一次商品查询的诊断信息（显示在「我的 → 错误信息」里，仅 iOS）。
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
    final jws = p.verificationData.serverVerificationData;
    try {
      await ApiService.instance.verifyApplePurchase(
        transactionId: p.purchaseID,
        signedTransaction: jws.split('.').length == 3 ? jws : null,
      );
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
