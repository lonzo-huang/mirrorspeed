// ============================================================
// 环境配置 — 替换为你的实际值
// 生产环境可通过 --dart-define=SUPABASE_URL=xxx 注入
// ============================================================

const String kSupabaseUrl  = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co');

const String kSupabaseAnon = String.fromEnvironment('SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key');

// Portal API 地址（和网页端同一个 Vercel 部署）
const String kApiBase      = String.fromEnvironment('API_BASE',
    defaultValue: 'https://portal.mirrorspeed.com');

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
// App ID 同时写入 AndroidManifest / Info.plist。
const String kAdMobAppId       = 'ca-app-pub-6444342069684995~8865360511';
const String kAdRewardedUnitId = 'ca-app-pub-6444342069684995/6183660776'; // 激励视频 → 延长试用
const String kAdAppOpenUnitId  = 'ca-app-pub-6444342069684995/6906245736'; // 开屏（可跳过）
// 每看完一条激励视频奖励的免费时长（分钟）
const int    kAdRewardMinutes  = 30;
