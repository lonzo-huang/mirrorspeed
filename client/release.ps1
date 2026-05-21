# ============================================================
# MirrorSpeed VPN — 一键构建 & 发布脚本
# 用法：
#   .\release.ps1 -Version 1.0.1
#   .\release.ps1 -Version 1.0.1 -SkipAndroid   # 只构建 Windows
#   .\release.ps1 -Version 1.0.1 -SkipWindows   # 只构建 Android
#   .\release.ps1 -Version 1.0.1 -DryRun        # 只构建，不发布到 GitHub
# ============================================================
param(
    [Parameter(Mandatory=$true)]
    [string]$Version,

    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── 配置 ──────────────────────────────────────────────────────
$SUPABASE_URL  = 'https://yqckjzfwibklwokialac.supabase.co'
$SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxY2tqemZ3aWJrbHdva2lhbGFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxOTY1MzcsImV4cCI6MjA5NDc3MjUzN30.NDxrGI6mgVMjgJvBchTkOCcT_ldiEEWtpJkFOhFGYNA'
$API_BASE      = 'https://mirrorspeed-portal.vercel.app'
$CRON_SECRET   = '7Hs2Ri8mhnBy3A4vdGFCKVSoc1qQYrPM'
$GITHUB_REPO   = 'lonzo-huang/mirrorspeed'
$TAG           = "v$Version"

$DEFINES = @(
    "--dart-define=SUPABASE_URL=$SUPABASE_URL",
    "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON",
    "--dart-define=API_BASE=$API_BASE"
)

# 构建产物路径
$APK_SRC  = "build\app\outputs\flutter-apk\app-release.apk"
$APK_DST  = "build\MirrorSpeed-$Version-android.apk"
$WIN_SRC  = "build\windows\x64\runner\Release"
$WIN_DST  = "build\MirrorSpeed-$Version-windows.zip"

# ── 工具函数 ──────────────────────────────────────────────────
function Write-Step([string]$msg) {
    Write-Host "`n━━━ $msg" -ForegroundColor Cyan
}
function Write-Ok([string]$msg) {
    Write-Host "  ✅ $msg" -ForegroundColor Green
}
function Write-Warn([string]$msg) {
    Write-Host "  ⚠️  $msg" -ForegroundColor Yellow
}
function Write-Fail([string]$msg) {
    Write-Host "  ❌ $msg" -ForegroundColor Red
    exit 1
}

# ── 前置检查 ──────────────────────────────────────────────────
Write-Step "前置检查"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { Write-Fail "未找到 flutter，请先安装 Flutter SDK" }
Write-Ok "Flutter: $(flutter --version --machine 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty frameworkVersion 2>$null ?? 'ok')"

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Fail "未找到 gh CLI，请先安装: winget install GitHub.cli" }
    $ghUser = gh api user --jq '.login' 2>$null
    if (-not $ghUser) { Write-Fail "gh 未登录，请运行: gh auth login" }
    Write-Ok "GitHub CLI: 已登录为 $ghUser"
}

# 检查 git tag 是否已存在
if (-not $DryRun) {
    $existingTag = git tag -l $TAG 2>$null
    if ($existingTag) { Write-Fail "Tag $TAG 已存在，请先删除: git tag -d $TAG && git push origin --delete $TAG" }
}

New-Item -ItemType Directory -Path build -Force | Out-Null
Write-Ok "版本: $Version  Tag: $TAG"

# ── 构建 Android APK ──────────────────────────────────────────
if (-not $SkipAndroid) {
    Write-Step "构建 Android APK"
    $startTime = Get-Date

    flutter build apk --release @DEFINES
    if ($LASTEXITCODE -ne 0) { Write-Fail "Flutter build apk 失败" }

    if (-not (Test-Path $APK_SRC)) { Write-Fail "APK 文件不存在: $APK_SRC" }

    Copy-Item $APK_SRC $APK_DST -Force
    $apkSize = [math]::Round((Get-Item $APK_DST).Length / 1MB, 1)
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
    Write-Ok "APK 构建完成：$APK_DST ($apkSize MB, ${elapsed}s)"
} else {
    Write-Warn "跳过 Android 构建"
}

# ── 构建 Windows ──────────────────────────────────────────────
if (-not $SkipWindows) {
    Write-Step "构建 Windows"
    $startTime = Get-Date

    flutter build windows --release @DEFINES
    if ($LASTEXITCODE -ne 0) { Write-Fail "Flutter build windows 失败" }

    if (-not (Test-Path $WIN_SRC)) { Write-Fail "Windows build 目录不存在: $WIN_SRC" }

    # 打包为 ZIP
    Write-Host "  📦 打包为 ZIP..."
    if (Test-Path $WIN_DST) { Remove-Item $WIN_DST -Force }
    Compress-Archive -Path "$WIN_SRC\*" -DestinationPath $WIN_DST
    $zipSize = [math]::Round((Get-Item $WIN_DST).Length / 1MB, 1)
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds)
    Write-Ok "Windows 构建完成：$WIN_DST ($zipSize MB, ${elapsed}s)"
} else {
    Write-Warn "跳过 Windows 构建"
}

# ── DryRun 模式：到此结束 ─────────────────────────────────────
if ($DryRun) {
    Write-Host "`n✅ DryRun 完成，构建产物：" -ForegroundColor Green
    if (Test-Path $APK_DST) { Write-Host "   APK: $APK_DST" }
    if (Test-Path $WIN_DST) { Write-Host "   WIN: $WIN_DST" }
    exit 0
}

# ── 创建 GitHub Release ───────────────────────────────────────
Write-Step "创建 GitHub Release: $TAG"

# 生成 release notes（可自定义）
$releaseNotes = @"
## MirrorSpeed VPN v$Version

### 下载说明
- **Android**：下载 APK 直接安装（需允许「未知来源」）
- **Windows**：下载 ZIP 解压后运行 `mirrorspeed_vpn.exe`（需要 WireGuard 驱动，首次运行请以管理员身份运行）

### 变更内容
- 请查看 [CHANGELOG](https://github.com/$GITHUB_REPO/blob/main/client/CHANGELOG.md)
"@

# 推送 tag
git tag $TAG
git push origin $TAG
Write-Ok "Tag $TAG 已推送"

# 创建 release
gh release create $TAG `
    --repo $GITHUB_REPO `
    --title "MirrorSpeed VPN v$Version" `
    --notes $releaseNotes

if ($LASTEXITCODE -ne 0) { Write-Fail "创建 GitHub Release 失败" }
Write-Ok "GitHub Release 创建成功"

# ── 上传文件 ──────────────────────────────────────────────────
Write-Step "上传构建产物"

if ((-not $SkipAndroid) -and (Test-Path $APK_DST)) {
    Write-Host "  ⬆️  上传 APK..."
    gh release upload $TAG $APK_DST `
        --repo $GITHUB_REPO `
        --clobber
    if ($LASTEXITCODE -ne 0) { Write-Fail "APK 上传失败" }
    Write-Ok "APK 上传成功"
}

if ((-not $SkipWindows) -and (Test-Path $WIN_DST)) {
    Write-Host "  ⬆️  上传 Windows ZIP..."
    gh release upload $TAG $WIN_DST `
        --repo $GITHUB_REPO `
        --clobber
    if ($LASTEXITCODE -ne 0) { Write-Fail "Windows ZIP 上传失败" }
    Write-Ok "Windows ZIP 上传成功"
}

# ── 触发 Vercel 页面缓存刷新 ──────────────────────────────────
Write-Step "刷新 Vercel 下载页面缓存"

try {
    $revalUrl  = "$API_BASE/api/revalidate?token=$CRON_SECRET&path=/download"
    $revalResp = Invoke-RestMethod -Uri $revalUrl -Method POST -ErrorAction Stop
    Write-Ok "页面缓存已刷新：$($revalResp | ConvertTo-Json -Compress)"
} catch {
    Write-Warn "页面缓存刷新失败（不影响发布）：$_"
}

# ── 完成 ──────────────────────────────────────────────────────
Write-Host ""
Write-Host "🎉 发布完成！" -ForegroundColor Green
Write-Host "   Release: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
Write-Host "   下载页:  $API_BASE/download"
Write-Host ""
