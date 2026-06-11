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
    // 连播激励广告期间，绝不插入开屏广告（避免在两条激励广告之间弹出打断）。
    if (!_supported || _showingFullScreen || _chaining) return;
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

  // ── 激励视频：预加载广告池，支持无缝连播 ───────────────────────
  // 维持一个 3 条的预加载池，连播时取一条立即补一条，避免「放完一条要等下一条」
  // 的卡顿/断链（断链会让用户被迫再点一次）。
  static const int _kRewardedPoolTarget = 3;
  final List<RewardedAd> _rewardedPool = [];
  int  _rewardedInFlight = 0;     // 正在加载中的数量
  int  _rewardedRetry    = 0;
  bool _chaining         = false; // 连播进行中（用于抑制开屏广告插入）

  /// 把池子补满到目标数量（幂等，可随时调用）。
  void loadRewarded() {
    if (!_supported) return;
    while (_rewardedPool.length + _rewardedInFlight < _kRewardedPoolTarget) {
      _rewardedInFlight++;
      RewardedAd.load(
        adUnitId: kAdRewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInFlight--;
            _rewardedPool.add(ad);
            _rewardedRetry = 0;
          },
          onAdFailedToLoad: (e) {
            _rewardedInFlight--;
            debugPrint('[Ad] rewarded load failed: $e');
            _retry(() => loadRewarded(), _rewardedRetry++);
          },
        ),
      );
    }
  }

  bool get rewardedReady => _supported && _rewardedPool.isNotEmpty;

  /// 提前预热：进入会展示激励广告的界面时调用，把池子提前填满（#4）。
  void warmUp() {
    if (!_supported) return;
    loadRewarded();
    loadAppOpen();
  }

  /// 展示单条激励视频，返回 (earned 是否获奖, watchedSec 本条观看秒数)。
  /// 从池中取一条并立即补池。
  Future<({bool earned, int watchedSec})> _showOne() {
    if (!_supported || _rewardedPool.isEmpty) {
      loadRewarded();
      return Future.value((earned: false, watchedSec: 0));
    }
    final ad = _rewardedPool.removeAt(0);
    loadRewarded();                 // 立即补池
    final completer = Completer<({bool earned, int watchedSec})>();
    _showingFullScreen = true;
    var earned = false;
    final start = DateTime.now();
    void finish(bool ok) {
      if (completer.isCompleted) return;
      final secs = ok ? DateTime.now().difference(start).inSeconds : 0;
      completer.complete((earned: ok, watchedSec: secs));
    }
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) { a.dispose(); _showingFullScreen = false; finish(earned); },
      onAdFailedToShowFullScreenContent: (a, e) { a.dispose(); _showingFullScreen = false; finish(false); },
    );
    ad.show(onUserEarnedReward: (a, reward) { earned = true; });
    return completer.future;
  }

  /// 等待池中出现可播广告（边等边补池），最多 [timeout]。
  Future<bool> _waitRewardedReady(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_rewardedPool.isNotEmpty) return true;
      loadRewarded();
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return _rewardedPool.isNotEmpty;
  }

  /// 连续播放激励广告，累计满 [targetSec] 秒（一条不够自动接着播下一条，
  /// 全程无需用户再次点击）。每条结束回调 [onProgress]（本条秒数, 累计秒数）；
  /// 用户中途跳过(未获奖)即停止。结束时回调 [onDone]（累计秒数, 是否达标）。
  Future<void> showRewardedChain({
    required int targetSec,
    void Function(int watchedSec, int totalSec)? onProgress,
    required void Function(int totalSec, bool reached) onDone,
  }) async {
    if (!_supported) { onDone(0, false); return; }
    _chaining = true;
    int total = 0;
    int shows = 0;
    try {
      // 最多连播 8 条，防止极端情况下无限循环。
      while (total < targetSec && shows < 8) {
        if (_rewardedPool.isEmpty) {
          final ok = await _waitRewardedReady(const Duration(seconds: 12));
          if (!ok) break;           // 始终拉不到广告 → 结束
        }
        final res = await _showOne();
        shows++;
        total += res.watchedSec;
        onProgress?.call(res.watchedSec, total);
        if (!res.earned) break;     // 用户跳过/未看完 → 停止连播
      }
    } finally {
      _chaining = false;
    }
    onDone(total, total >= targetSec);
  }

  // 加载失败按指数退避重试（最多 ~5 次：5s,10s,20s,40s,80s），缓解新账号填充慢。
  void _retry(void Function() fn, int attempt) {
    if (!_supported || attempt >= 5) return;
    final secs = 5 * (1 << attempt);
    Timer(Duration(seconds: secs), fn);
  }
}
