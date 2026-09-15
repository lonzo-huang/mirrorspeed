import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../env.dart';

/// 应用内购（目前仅 iOS）。
///
/// 苹果规定 iOS 上出售数字商品必须走内购，且不得在 App 内引导去网页支付。
/// 安卓 / Windows / macOS 仍走官网支付，本服务在这些平台直接空转。
///
/// 流程：
///   1. queryProducts 从 App Store 拉取本地化价格（苹果要求显示当地货币，不能写死）
///   2. buy(plan) 发起购买，appAccountToken 带上我方 user id，便于服务端对账
///   3. 购买/恢复的交易上报 `/api/mobile/iap/apple` 由服务器验签落库
///   4. 会员状态一律以服务器为准（AuthProvider 重新拉配置）
class IapService {
  IapService._();
  static final IapService instance = IapService._();

  /// 仅 iOS 启用。macOS 虽然也能接内购，但当前 Mac 版走官网支付。
  static bool get supported => !kIsWeb && Platform.isIOS;

  /// 套餐 id → App Store 产品 id（需与 App Store Connect 里创建的完全一致，
  /// 也要与后端 plans.apple_product_id 对应）。
  static const Map<String, String> productIds = {
    'monthly':  'com.mirrorspeed.vip.monthly',
    'quarterly': 'com.mirrorspeed.vip.quarterly',
    'halfyear': 'com.mirrorspeed.vip.halfyear',
    'yearly':   'com.mirrorspeed.vip.yearly',
    'biennial': 'com.mirrorspeed.vip.biennial',
  };

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// planId → 商品（含本地化价格串）
  final Map<String, ProductDetails> _products = {};
  Map<String, ProductDetails> get products => _products;

  bool _available = false;
  bool get available => _available;

  /// 购买/恢复成功并被服务器确认后回调（用于刷新会员状态）。
  Future<void> Function()? onEntitlementChanged;

  /// 购买流程中的错误（展示给用户）。
  final ValueNotifier<String?> error = ValueNotifier(null);
  /// 是否有购买正在进行（界面转圈用）。
  final ValueNotifier<bool> busy = ValueNotifier(false);

  Future<void> initialize() async {
    if (!supported || _sub != null) return;
    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      debugPrint('[IAP] isAvailable 失败: $e');
      _available = false;
    }
    if (!_available) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => debugPrint('[IAP] purchaseStream 错误: $e'),
    );
    await queryProducts();
  }

  Future<void> queryProducts() async {
    if (!supported || !_available) return;
    try {
      final resp = await _iap.queryProductDetails(productIds.values.toSet());
      if (resp.notFoundIDs.isNotEmpty) {
        debugPrint('[IAP] App Store 未找到这些产品: ${resp.notFoundIDs}');
      }
      for (final entry in productIds.entries) {
        final p = resp.productDetails.where((d) => d.id == entry.value).firstOrNull;
        if (p != null) _products[entry.key] = p;
      }
    } catch (e) {
      debugPrint('[IAP] 查询商品失败: $e');
    }
  }

  /// 发起购买。[planId] 见 [productIds]。
  Future<void> buy(String planId) async {
    if (!supported) return;
    final product = _products[planId];
    if (product == null) {
      error.value = '暂时无法获取该套餐价格，请稍后重试';
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      error.value = '请先登录再购买';
      return;
    }
    busy.value = true;
    error.value = null;
    try {
      // appAccountToken 必须是 UUID；Supabase 的 user id 正好是 UUID。
      // 服务端可据此把交易与账号对上（即便用户换了 Apple ID）。
      final param = PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      );
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      busy.value = false;
      error.value = '$e';
    }
  }

  /// 恢复购买（苹果强制要求提供入口：换设备/重装后要能拿回会员）。
  Future<void> restore() async {
    if (!supported) return;
    busy.value = true;
    error.value = null;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      error.value = '$e';
    } finally {
      busy.value = false;
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy.value = true;
          break;

        case PurchaseStatus.error:
          busy.value = false;
          error.value = p.error?.message ?? '购买失败';
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;

        case PurchaseStatus.canceled:
          busy.value = false;
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await _verifyWithServer(p);
          // 只有服务器确认后才 complete：否则交易会一直挂在队列里，
          // 下次启动还能重试上报，不会因为一次网络失败就丢掉已付款的订阅。
          if (ok && p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          busy.value = false;
          if (ok) await onEntitlementChanged?.call();
          break;
      }
    }
  }

  /// 把 StoreKit 2 的签名交易发给服务器验签落库。
  Future<bool> _verifyWithServer(PurchaseDetails p) async {
    final jws = p.verificationData.serverVerificationData;
    if (jws.isEmpty) return false;
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      error.value = '登录已过期，请重新登录后在「我的」里点恢复购买';
      return false;
    }
    try {
      final res = await http.post(
        Uri.parse('$kApiBase/api/mobile/iap/apple'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'signed_transactions': [jws]}),
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return true;
      debugPrint('[IAP] 服务器校验失败 ${res.statusCode}: ${res.body}');
      error.value = '购买已完成，但激活会员失败，请稍后在「我的」里点恢复购买';
      return false;
    } catch (e) {
      debugPrint('[IAP] 上报失败: $e');
      error.value = '网络异常，购买已完成但未激活；联网后点恢复购买即可';
      return false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
