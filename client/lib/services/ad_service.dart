import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../env.dart';

/// AdMob 封装：开屏(App Open，可跳过) + 激励视频(Rewarded，看完延长试用)。
/// 仅 Android / iOS 生效；Windows / Web 上全部为安全空操作。
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool _initialized = false;
  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      loadAppOpen();
      loadRewarded();
    } catch (e) {
      debugPrint('[Ad] init failed: $e');
    }
  }

  // ── 开屏广告（可跳过：全屏自带关闭，用户点 X 即跳过）────────────
  AppOpenAd? _appOpenAd;
  bool _showingFullScreen = false;

  void loadAppOpen() {
    if (!_supported || _appOpenAd != null) return;
    AppOpenAd.load(
      adUnitId: kAdAppOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) => _appOpenAd = ad,
        onAdFailedToLoad: (e) {
          _appOpenAd = null;
          debugPrint('[Ad] appOpen load failed: $e');
        },
      ),
    );
  }

  /// 启动时调用：已加载则展示开屏；未加载则静默跳过并预加载（绝不阻塞启动）。
  void showAppOpenIfAvailable() {
    if (!_supported || _showingFullScreen) return;
    final ad = _appOpenAd;
    if (ad == null) {
      loadAppOpen();
      return;
    }
    _appOpenAd = null;
    _showingFullScreen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showingFullScreen = false;
        loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showingFullScreen = false;
        loadAppOpen();
      },
    );
    ad.show();
  }

  // ── 激励视频（看完 → onReward）──────────────────────────────────
  RewardedAd? _rewarded;
  bool _loadingRewarded = false;

  void loadRewarded() {
    if (!_supported || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: kAdRewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loadingRewarded = false;
        },
        onAdFailedToLoad: (e) {
          _rewarded = null;
          _loadingRewarded = false;
          debugPrint('[Ad] rewarded load failed: $e');
        },
      ),
    );
  }

  bool get rewardedReady => _supported && _rewarded != null;

  /// 展示激励视频。看完触发 [onReward]；展示结束触发 [onClosed]。
  /// 未就绪则触发预加载并立即 onClosed(false)。
  void showRewarded({
    required void Function() onReward,
    void Function(bool rewarded)? onClosed,
  }) {
    if (!_supported) {
      onClosed?.call(false);
      return;
    }
    final ad = _rewarded;
    if (ad == null) {
      loadRewarded();
      onClosed?.call(false);
      return;
    }
    _rewarded = null;
    _showingFullScreen = true;
    var rewarded = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showingFullScreen = false;
        loadRewarded();
        onClosed?.call(rewarded);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showingFullScreen = false;
        loadRewarded();
        onClosed?.call(false);
      },
    );
    ad.show(onUserEarnedReward: (a, reward) {
      rewarded = true;
      onReward();
    });
  }
}
