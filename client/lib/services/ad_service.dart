import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../env.dart';

/// AdMob 封装：开屏(App Open，可跳过) + 激励视频(Rewarded，看完延长试用)。
/// 仅 Android / iOS 生效；Windows / Web 上全部为安全空操作。
/// 付费会员通过 initialize(enabled:false) 关闭所有广告（#2）。
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  bool get _platformOk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool _enabled = true;                 // 付费会员为 false
  bool get _supported => _platformOk && _enabled;

  bool _initialized = false;
  Future<void> initialize({bool enabled = true}) async {
    _enabled = enabled;
    if (!_platformOk || !enabled || _initialized) return;
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
  int _appOpenRetry = 0;

  void loadAppOpen() {
    if (!_supported || _appOpenAd != null) return;
    AppOpenAd.load(
      adUnitId: kAdAppOpenUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) { _appOpenAd = ad; _appOpenRetry = 0; },
        onAdFailedToLoad: (e) {
          _appOpenAd = null;
          debugPrint('[Ad] appOpen load failed: $e');
          _retry(() => loadAppOpen(), _appOpenRetry++);
        },
      ),
    );
  }

  /// 启动时调用：已加载则展示开屏；未加载则静默跳过并预加载（绝不阻塞启动）。
  void showAppOpenIfAvailable() {
    if (!_supported || _showingFullScreen) return;
    final ad = _appOpenAd;
    if (ad == null) { loadAppOpen(); return; }
    _appOpenAd = null;
    _showingFullScreen = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose(); _showingFullScreen = false; loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose(); _showingFullScreen = false; loadAppOpen();
      },
    );
    ad.show();
  }

  // ── 激励视频（看完 → onReward）──────────────────────────────────
  RewardedAd? _rewarded;
  bool _loadingRewarded = false;
  int _rewardedRetry = 0;

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
          _rewardedRetry = 0;
        },
        onAdFailedToLoad: (e) {
          _rewarded = null;
          _loadingRewarded = false;
          debugPrint('[Ad] rewarded load failed: $e');
          _retry(() => loadRewarded(), _rewardedRetry++);
        },
      ),
    );
  }

  bool get rewardedReady => _supported && _rewarded != null;

  /// 提前预热：进入会展示激励广告的界面时调用，确保点击时已就绪（#4）。
  void warmUp() {
    if (!_supported) return;
    loadRewarded();
    loadAppOpen();
  }

  /// 展示激励视频。[onClosed] 回报 (earned 是否看到奖励点, watchedSec 本条观看秒数)。
  /// 未就绪则触发预加载并立即 onClosed(false, 0)。
  void showRewarded({
    void Function()? onReward,
    void Function(bool earned, int watchedSec)? onClosed,
  }) {
    if (!_supported) { onClosed?.call(false, 0); return; }
    final ad = _rewarded;
    if (ad == null) { loadRewarded(); onClosed?.call(false, 0); return; }
    _rewarded = null;
    _showingFullScreen = true;
    var earned = false;
    final start = DateTime.now();
    void finish(bool ok) {
      final secs = ok ? DateTime.now().difference(start).inSeconds : 0;
      onClosed?.call(ok, secs);
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose(); _showingFullScreen = false; loadRewarded(); finish(earned);
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose(); _showingFullScreen = false; loadRewarded(); finish(false);
      },
    );
    ad.show(onUserEarnedReward: (a, reward) { earned = true; onReward?.call(); });
  }

  // 加载失败按指数退避重试（最多 ~5 次：5s,10s,20s,40s,80s），缓解新账号填充慢。
  void _retry(void Function() fn, int attempt) {
    if (!_supported || attempt >= 5) return;
    final secs = 5 * (1 << attempt);
    Timer(Duration(seconds: secs), fn);
  }
}
