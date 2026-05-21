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

// OAuth 回调 URL Scheme
const String kAuthCallbackScheme = 'mirrorspeed';
const String kAuthCallbackUrl    = '$kAuthCallbackScheme://login-callback';
