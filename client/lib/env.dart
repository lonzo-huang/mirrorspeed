import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
// ============================================================
// 环境配置 — 替换为你的实际值
// 生产环境可通过 --dart-define=SUPABASE_URL=xxx 注入
// ============================================================

const String kSupabaseUrl  = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co');

const String kSupabaseAnon = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key');

// Portal API 地址（和网页端同一个 Vercel 部署）。
// 主域名 + 兜底域名：主域名被 GFW 封锁（DNS 污染 / SNI 阻断）连不上时，
// 客户端自动切到兜底域名。兜底域名须指向【同一个 Vercel 部署】、提供相同 API。
// 两个域名都在 Vercel 项目 Domains 里添加即可（自动签 TLS）。
const String kApiBase         = String.fromEnvironment('API_BASE',
    defaultValue: 'https://portal.mirrorspeed.com');
const String kApiBaseFallback = String.fromEnvironment('API_BASE_FALLBACK',
    defaultValue: 'https://mirrorspeed.eu.cc');

/// 引导域名候选（按优先级）。为空项自动剔除，便于只配一个时降级。
List<String> get kApiBases => [
      kApiBase,
      kApiBaseFallback,
    ].where((e) => e.isNotEmpty).toList();

// iOS Network Extension Bundle ID（须与 Xcode 配置一致）
const String kProviderBundle = 'com.mirrorspeed.vpn.network';

// ── 双壳（Brand）────────────────────────────────────────────────
// 已合并为单一安装包(com.mirrorspeed.vpn)，不再用编译期 flavor。
// App 内文案 / 功能差异统一走运行时 `Brand`（见 lib/brand.dart）：
// 中文壳=镜速加速器（合规，不显示 VPN 字样），其它=MirrorSpeed VPN。

// OAuth 回调 URL Scheme（单一；与 AndroidManifest deepLinkScheme 一致）
const String kAuthCallbackScheme = 'mirrorspeed';
const String kAuthCallbackUrl    = '$kAuthCallbackScheme://login-callback';

// ── AdMob 广告（仅 Android/iOS）──────────────────────────────────
// AdMob 的 App ID / 广告位 ID 是分平台的，用错平台会被判为无效请求拿不到广告。
// App ID 另需写入 AndroidManifest（安卓）/ Info.plist（iOS）。
bool get _isIOS => !kIsWeb && Platform.isIOS;

// 安卓
const String _kAdMobAppIdAndroid       = 'ca-app-pub-6444342069684995~8865360511';
const String _kAdRewardedUnitIdAndroid = 'ca-app-pub-6444342069684995/6183660776';
const String _kAdAppOpenUnitIdAndroid  = 'ca-app-pub-6444342069684995/6906245736';
// iOS
const String _kAdMobAppIdIOS           = 'ca-app-pub-6444342069684995~4402982650';
const String _kAdRewardedUnitIdIOS     = 'ca-app-pub-6444342069684995/5669806179';
const String _kAdAppOpenUnitIdIOS      = 'ca-app-pub-6444342069684995/1263657308';

String get kAdMobAppId       => _isIOS ? _kAdMobAppIdIOS       : _kAdMobAppIdAndroid;
String get kAdRewardedUnitId => _isIOS ? _kAdRewardedUnitIdIOS : _kAdRewardedUnitIdAndroid;
String get kAdAppOpenUnitId  => _isIOS ? _kAdAppOpenUnitIdIOS  : _kAdAppOpenUnitIdAndroid;
// 每看完一条激励视频奖励的免费时长（分钟）
const int    kAdRewardMinutes  = 30;

// ── iOS 站外支付入口开关 ─────────────────────────────────────────
// 苹果的 anti-steering 条款禁止在 App 内引导用户去网页购买数字商品，带这类入口
// 会被拒审，所以 iOS 上默认隐藏「官网购买」（安卓/Windows/macOS 不受影响）。
// 若将来申请到 External Purchase Link 权限（美区/欧盟等），改成 true 即可恢复。
const bool kAllowWebPurchaseOnIOS = false;
