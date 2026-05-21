# MirrorSpeed VPN - Build & Release Script
# Usage:
#   .\release.ps1 1.0.1
#   .\release.ps1 1.0.1 -SkipAndroid
#   .\release.ps1 1.0.1 -SkipWindows
#   .\release.ps1 1.0.1 -DryRun

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Version,
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Config ------------------------------------------------------------------
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

$APK_SRC = "build\app\outputs\flutter-apk\app-release.apk"
$APK_DST = "build\MirrorSpeed-$Version-android.apk"
$WIN_SRC = "build\windows\x64\runner\Release"
$WIN_DST = "build\MirrorSpeed-$Version-windows.zip"

# --- Helpers -----------------------------------------------------------------
function Step([string]$msg)  { Write-Host "`n--- $msg" -ForegroundColor Cyan }
function Ok([string]$msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn([string]$msg)  { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Fail([string]$msg)  { Write-Host "  [FAIL] $msg" -ForegroundColor Red; exit 1 }

# --- Pre-flight checks -------------------------------------------------------
Step "Pre-flight checks"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail "flutter not found. Install Flutter SDK first."
}
Ok "flutter found"

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail "gh CLI not found. Install with: winget install GitHub.cli"
    }
    $ghStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Fail "gh not logged in. Run: gh auth login"
    }
    Ok "gh CLI authenticated"

    $existingTag = git tag -l $TAG 2>$null
    if ($existingTag) {
        Fail "Tag $TAG already exists. Delete first: git tag -d $TAG  then  git push origin --delete $TAG"
    }
}

New-Item -ItemType Directory -Path build -Force | Out-Null
Ok "Version=$Version  Tag=$TAG  DryRun=$DryRun"

# --- Build Android APK -------------------------------------------------------
if (-not $SkipAndroid) {
    Step "Building Android APK"
    $t0 = Get-Date

    flutter build apk --release @DEFINES
    if ($LASTEXITCODE -ne 0) { Fail "flutter build apk failed" }

    if (-not (Test-Path $APK_SRC)) { Fail "APK not found at: $APK_SRC" }
    Copy-Item $APK_SRC $APK_DST -Force

    $mb  = [math]::Round((Get-Item $APK_DST).Length / 1MB, 1)
    $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds)
    Ok "APK ready: $APK_DST  ($mb MB, ${sec}s)"
} else {
    Warn "Skipping Android build"
}

# --- Build Windows -----------------------------------------------------------
if (-not $SkipWindows) {
    Step "Building Windows"
    $t0 = Get-Date

    flutter build windows --release @DEFINES
    if ($LASTEXITCODE -ne 0) { Fail "flutter build windows failed" }

    if (-not (Test-Path $WIN_SRC)) { Fail "Windows build dir not found: $WIN_SRC" }

    Write-Host "  Packaging as ZIP..."
    if (Test-Path $WIN_DST) { Remove-Item $WIN_DST -Force }
    Compress-Archive -Path "$WIN_SRC\*" -DestinationPath $WIN_DST

    $mb  = [math]::Round((Get-Item $WIN_DST).Length / 1MB, 1)
    $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds)
    Ok "Windows ZIP ready: $WIN_DST  ($mb MB, ${sec}s)"
} else {
    Warn "Skipping Windows build"
}

# --- DryRun: stop here -------------------------------------------------------
if ($DryRun) {
    Write-Host "`nDryRun complete. Artifacts:" -ForegroundColor Green
    if (Test-Path $APK_DST) { Write-Host "  APK: $APK_DST" }
    if (Test-Path $WIN_DST) { Write-Host "  WIN: $WIN_DST" }
    exit 0
}

# --- Create GitHub Release ---------------------------------------------------
Step "Creating GitHub Release: $TAG"

$notes = "## MirrorSpeed VPN v$Version`n`n" +
         "**Android**: Download APK and install (allow unknown sources)`n" +
         "**Windows**: Download ZIP, extract and run mirrorspeed_vpn.exe (run as admin on first launch for WireGuard driver)"

git tag $TAG
if ($LASTEXITCODE -ne 0) { Fail "git tag failed" }

git push origin $TAG
if ($LASTEXITCODE -ne 0) { Fail "git push tag failed" }
Ok "Tag $TAG pushed"

gh release create $TAG `
    --repo $GITHUB_REPO `
    --title "MirrorSpeed VPN v$Version" `
    --notes $notes

if ($LASTEXITCODE -ne 0) { Fail "gh release create failed" }
Ok "GitHub Release created"

# --- Upload artifacts --------------------------------------------------------
Step "Uploading artifacts"

if ((-not $SkipAndroid) -and (Test-Path $APK_DST)) {
    Write-Host "  Uploading APK..."
    gh release upload $TAG $APK_DST --repo $GITHUB_REPO --clobber
    if ($LASTEXITCODE -ne 0) { Fail "APK upload failed" }
    Ok "APK uploaded"
}

if ((-not $SkipWindows) -and (Test-Path $WIN_DST)) {
    Write-Host "  Uploading Windows ZIP..."
    gh release upload $TAG $WIN_DST --repo $GITHUB_REPO --clobber
    if ($LASTEXITCODE -ne 0) { Fail "Windows ZIP upload failed" }
    Ok "Windows ZIP uploaded"
}

# --- Trigger Vercel cache revalidation ---------------------------------------
Step "Revalidating Vercel download page"

try {
    $url  = "$API_BASE/api/revalidate?token=$CRON_SECRET&path=/download"
    $resp = Invoke-RestMethod -Uri $url -Method POST -ErrorAction Stop
    Ok "Cache revalidated"
} catch {
    Warn "Revalidation failed (release is still live): $_"
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "Release complete!" -ForegroundColor Green
Write-Host "  Release : https://github.com/$GITHUB_REPO/releases/tag/$TAG"
Write-Host "  Download: $API_BASE/download"
Write-Host ""
