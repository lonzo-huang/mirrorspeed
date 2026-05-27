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

// ── 应用版本（Flavor）────────────────────────────────────────
// 构建时通过 --dart-define=APP_FLAVOR=cn|global 注入
// cn    = 镜速加速器（国内版，含智能路由）
// global = MirrorSpeed VPN（国际版）
const String kAppFlavor  = String.fromEnvironment('APP_FLAVOR', defaultValue: 'global');
const bool   kIsCnFlavor = kAppFlavor == 'cn';

// OAuth 回调 URL Scheme（与 AndroidManifest deepLinkScheme 一致）
const String kAuthCallbackScheme = kIsCnFlavor ? 'jinsuapp' : 'mirrorspeed';
const String kAuthCallbackUrl    = '$kAuthCallbackScheme://login-callback';
