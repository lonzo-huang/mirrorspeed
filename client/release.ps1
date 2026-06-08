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
    [switch]$DryRun,
    # Re-release ONLY the Windows artifact for an already-published tag:
    # skips Android, skips the version bump, and reuses the existing GitHub
    # Release + tag (clobber-uploads the new zip + refreshes the CN mirror).
    [switch]$WindowsOnly
)

if ($WindowsOnly) { $SkipAndroid = $true }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Config ------------------------------------------------------------------
$SUPABASE_URL  = 'https://yqckjzfwibklwokialac.supabase.co'
$SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxY2tqemZ3aWJrbHdva2lhbGFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxOTY1MzcsImV4cCI6MjA5NDc3MjUzN30.NDxrGI6mgVMjgJvBchTkOCcT_ldiEEWtpJkFOhFGYNA'
$API_BASE      = 'https://www.mirrorspeed.com'
$CRON_SECRET   = 'lFCBNQtNmuEpIclLTTMhvfqgb2FDX9Pj'
$GITHUB_REPO   = 'lonzo-huang/mirrorspeed'
$TAG           = "v$Version"

$DEFINES = @(
    "--dart-define=SUPABASE_URL=$SUPABASE_URL",
    "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON",
    "--dart-define=API_BASE=$API_BASE"
)

# Single APK (flavors merged; shell switches by device locale at runtime).
# --split-per-abi 产出每个架构一个【干净】的单架构包；直接下载取 arm64-v8a。
$APK_SRC = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
$APK_DST = "build\MirrorSpeed-$Version-android.apk"
# App Bundle for Google Play (Play delivers per-device ABI).
$AAB_SRC = "build\app\outputs\bundle\release\app-release.aab"
$AAB_DST = "build\MirrorSpeed-$Version-android.aab"
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
    gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "gh not logged in. Run: gh auth login"
    }
    Ok "gh CLI authenticated"

    $existingTag = git tag -l $TAG 2>$null
    if ($existingTag -and -not $WindowsOnly) {
        Fail "Tag $TAG already exists. Delete first: git tag -d $TAG  then  git push origin --delete $TAG"
    }
    if ($WindowsOnly -and -not $existingTag) {
        Fail "-WindowsOnly expects tag $TAG to already exist, but it does not."
    }
}

New-Item -ItemType Directory -Path build -Force | Out-Null
Ok "Version=$Version  Tag=$TAG  DryRun=$DryRun"

# --- Bump version in pubspec.yaml and lib/version.dart -----------------------
if ($WindowsOnly) {
    Step "Skipping version bump (-WindowsOnly re-release of existing $TAG)"
}
if (-not $WindowsOnly) {
Step "Bumping version files to $Version"
$pubspecPath  = Join-Path $PSScriptRoot "pubspec.yaml"
$versionDart  = Join-Path $PSScriptRoot "lib\version.dart"

# Use Python to safely edit pubspec.yaml (avoids PowerShell UTF-8/encoding issues)
$pyScript = @"
import re, sys
path = sys.argv[1]
ver  = sys.argv[2]
with open(path, encoding='utf-8') as f:
    txt = f.read()
m = re.search(r'^version:\s+[\d.]+\+(\d+)', txt, re.MULTILINE)
build = (int(m.group(1)) + 1) if m else 1
new_ver_line = f'version: {ver}+{build}'
# Only replace the standalone version: line (not inside description or comments)
txt2 = re.sub(r'^version:\s+[\d.]+\+\d+', new_ver_line, txt, flags=re.MULTILINE)
with open(path, 'w', encoding='utf-8') as f:
    f.write(txt2)
print(f'{ver}+{build}')
"@
$pyScript | Out-File -Encoding utf8 -FilePath "$env:TEMP\bump_pubspec.py"
$newVerFull = python "$env:TEMP\bump_pubspec.py" "$pubspecPath" "$Version" 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Failed to update pubspec.yaml: $newVerFull" }
Ok "pubspec.yaml → version: $newVerFull"

# Write version.dart using Python to ensure UTF-8 without BOM
$pyDart = @"
import sys
path, ver = sys.argv[1], sys.argv[2]
content = f'''// Auto-updated by the release script -- do not edit manually.
// Keep in sync with pubspec.yaml version field.
const String kAppVersion = '{ver}';
'''
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
"@
$pyDart | Out-File -Encoding utf8 -FilePath "$env:TEMP\write_version_dart.py"
python "$env:TEMP\write_version_dart.py" "$versionDart" "$Version" 2>&1
if ($LASTEXITCODE -ne 0) { Fail "Failed to update lib/version.dart" }
Ok "lib/version.dart → kAppVersion = '$Version'"
}  # end if (-not $WindowsOnly) version bump

# --- Stop stale Gradle/Kotlin daemons BEFORE cleaning ------------------------
Step "Stopping Gradle daemons + cleaning build cache"
Write-Host "  Stopping Gradle/Kotlin daemons..."
$androidGradlew = Join-Path $PSScriptRoot "android\gradlew.bat"
if (Test-Path $androidGradlew) {
    $ErrorActionPreference = 'Continue'
    & $androidGradlew --stop 2>$null
    $ErrorActionPreference = 'Stop'
}
# Also kill any lingering java processes from previous builds
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$ErrorActionPreference = 'Continue'; flutter clean;   $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
if ($ec -ne 0) { Fail "flutter clean failed" }
$ErrorActionPreference = 'Continue'; flutter pub get; $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
if ($ec -ne 0) { Fail "flutter pub get failed" }
Ok "Clean done"

# --- Build Android APK (clean arm64-v8a via abiFilters) + App Bundle (Play) --
if (-not $SkipAndroid) {
    # Clean single-ABI APK: abiFilters strips EVERY non-arm64 native lib (incl.
    # third-party jniLibs), avoiding the malformed "arm64 complete + other ABIs
    # partial" package that some installers reject with "parse failed".
    Step "Building Android APK (clean arm64-v8a via --split-per-abi)"
    $t0 = Get-Date

    $ErrorActionPreference = 'Continue'
    flutter build apk --release --split-per-abi --no-tree-shake-icons @DEFINES
    $ec = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Fail "flutter build apk failed" }

    if (-not (Test-Path $APK_SRC)) { Fail "APK not found at: $APK_SRC" }
    Copy-Item $APK_SRC $APK_DST -Force

    $mb  = [math]::Round((Get-Item $APK_DST).Length / 1MB, 1)
    $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds)
    Ok "APK ready: $APK_DST  ($mb MB, ${sec}s)"

    # App Bundle for Google Play (all ABIs; Play splits per-device). MS_TARGET_ABI
    # is intentionally NOT set here so the bundle keeps every architecture.
    Step "Building Android App Bundle (.aab - Google Play)"
    $t0 = Get-Date
    $ErrorActionPreference = 'Continue'
    flutter build appbundle --release --no-tree-shake-icons @DEFINES
    $ec = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Fail "flutter build appbundle failed" }
    if (-not (Test-Path $AAB_SRC)) { Fail "AAB not found at: $AAB_SRC" }
    Copy-Item $AAB_SRC $AAB_DST -Force
    $mb  = [math]::Round((Get-Item $AAB_DST).Length / 1MB, 1)
    $sec = [math]::Round(((Get-Date) - $t0).TotalSeconds)
    Ok "AAB ready: $AAB_DST  ($mb MB, ${sec}s)"
} else {
    Warn "Skipping Android build"
}

# --- Build Windows -----------------------------------------------------------
if (-not $SkipWindows) {
    Step "Building Windows"
    $t0 = Get-Date

    # --obfuscate replaces Dart class/function names with random identifiers
    # --split-debug-info keeps debug symbols separate (required with --obfuscate)
    $ErrorActionPreference = 'Continue'
    flutter build windows --release --no-tree-shake-icons --obfuscate --split-debug-info=build/debug_symbols/windows @DEFINES
    $ec = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Fail "flutter build windows failed" }

    if (-not (Test-Path $WIN_SRC)) { Fail "Windows build dir not found: $WIN_SRC" }

    # --- Post-build: rename tell-tale DLL names --------------------------------
    # Patches PE import-table strings in-place (same byte length = no RVA shift)
    # then renames the actual files to match.
    #
    # Mappings (all replacements are the same byte length as the original):
    #   flutter_windows.dll                      (19) -> app_core_render.dll                      (19)
    #   wireguard_flutter_plugin.dll             (28) -> ms_network_security_core.dll             (28)
    #   flutter_secure_storage_windows_plugin.dll(41) -> ms_secure_data_store_windows_plugin_x.dll(41)
    #
    # NOTE: flutter_assets folder is NOT renamed.
    # Flutter engine loads MaterialIcons and all assets from data\flutter_assets\.
    # Renaming the folder breaks font loading → all icons render as blank boxes.
    # The Flutter engine stores this path as UTF-16 wide strings internally,
    # which a simple ASCII byte-patch cannot fix.
    #
    # NOTE: wireguard.dll and wireguard_svc.exe are NOT renamed.
    # They use UTF-16 wide strings internally to reference each other,
    # which a simple ASCII byte-patch cannot fix without breaking VPN functionality.

    Step "Obfuscating Windows build (DLL rename + asset folder rename)"

    function Patch-PE {
        param(
            [string]$File,
            [string]$OldStr,
            [string]$NewStr
        )
        if (-not (Test-Path $File)) { return }
        $old = [System.Text.Encoding]::ASCII.GetBytes($OldStr + "`0")
        $new = [System.Text.Encoding]::ASCII.GetBytes($NewStr + "`0")
        if ($old.Length -ne $new.Length) {
            Write-Host "  [SKIP] Length mismatch for '$OldStr' vs '$NewStr'" -ForegroundColor Yellow
            return
        }
        $bytes = [System.IO.File]::ReadAllBytes($File)
        $hits  = 0
        for ($i = 0; $i -le ($bytes.Length - $old.Length); $i++) {
            $match = $true
            for ($j = 0; $j -lt $old.Length; $j++) {
                if ($bytes[$i + $j] -ne $old[$j]) { $match = $false; break }
            }
            if ($match) {
                for ($j = 0; $j -lt $new.Length; $j++) { $bytes[$i + $j] = $new[$j] }
                $hits++
            }
        }
        [System.IO.File]::WriteAllBytes($File, $bytes)
        if ($hits -gt 0) {
            Write-Host ("  Patched {0}: '{1}' x{2}" -f ([System.IO.Path]::GetFileName($File)), $OldStr, $hits)
        }
    }

    # Patch ALL exe/dll files in the release dir for every rename
    $allBinaries = Get-ChildItem -Path $WIN_SRC -Include "*.exe","*.dll" -Recurse

    foreach ($bin in $allBinaries) {
        Patch-PE $bin.FullName "flutter_windows.dll"                       "app_core_render.dll"
        Patch-PE $bin.FullName "amneziawg_flutter_plugin.dll"              "ms_network_security_core.dll"
        Patch-PE $bin.FullName "flutter_secure_storage_windows_plugin.dll" "ms_secure_data_store_windows_plugin_x.dll"
        # flutter_assets NOT patched/renamed — see comment above
    }

    # Rename DLL / EXE files (Move-Item -Force overwrites if target already exists)
    if (Test-Path "$WIN_SRC\flutter_windows.dll") {
        Move-Item "$WIN_SRC\flutter_windows.dll" "$WIN_SRC\app_core_render.dll" -Force
        Ok "flutter_windows.dll -> app_core_render.dll"
    }
    if (Test-Path "$WIN_SRC\amneziawg_flutter_plugin.dll") {
        Move-Item "$WIN_SRC\amneziawg_flutter_plugin.dll" "$WIN_SRC\ms_network_security_core.dll" -Force
        Ok "amneziawg_flutter_plugin.dll -> ms_network_security_core.dll"
    }
    if (Test-Path "$WIN_SRC\flutter_secure_storage_windows_plugin.dll") {
        Move-Item "$WIN_SRC\flutter_secure_storage_windows_plugin.dll" "$WIN_SRC\ms_secure_data_store_windows_plugin_x.dll" -Force
        Ok "flutter_secure_storage_windows_plugin.dll -> ms_secure_data_store_windows_plugin_x.dll"
    }



    Ok "Obfuscation done"

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
    if (Test-Path $WIN_DST)        { Write-Host "  WIN:          $WIN_DST" }
    exit 0
}

# --- Create GitHub Release ---------------------------------------------------
if ($WindowsOnly) {
    Step "Re-releasing Windows only — reusing existing tag/release $TAG"
}
if (-not $WindowsOnly) {
Step "Creating GitHub Release: $TAG"

$notes = "## MirrorSpeed VPN v$Version`n`n" +
         "### What's new`n" +
         "- Connection now shows the active mode: Fast (UDP) / Strong (TCP relay) / Ultra (Cloudflare)`n" +
         "- Status stays ""Connecting"" until traffic is verified — ""Connected"" only when it really works`n" +
         "- Manual disconnect is final (no more auto-switching to the next mode)`n" +
         "- Routes are always cleaned up on exit/failure (no more dead tunnels blackholing traffic)`n" +
         "- Node list shows a colored latency dot (green/amber/red) instead of raw numbers`n" +
         "- App opens straight to the connect screen; sign in from ""Me"" when you want`n" +
         "- 3-digit verification code with auto-submit`n" +
         "- Narrower, phone-style window on Windows`n`n" +
         "### Install`n" +
         "**Android**: download the APK and install (allow unknown sources)`n" +
         "**Windows**: download the ZIP, extract, and run mirrorspeed_vpn.exe (right-click → Run as administrator on first launch)"

$ErrorActionPreference = 'Continue'
git tag $TAG
$ec = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($ec -ne 0) { Fail "git tag failed" }

$ErrorActionPreference = 'Continue'
git push origin $TAG
$ec = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($ec -ne 0) { Fail "git push tag failed" }
Ok "Tag $TAG pushed"

$ErrorActionPreference = 'Continue'
gh release create $TAG `
    --repo $GITHUB_REPO `
    --title "MirrorSpeed VPN v$Version" `
    --notes $notes
$ec = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($ec -ne 0) { Fail "gh release create failed" }
Ok "GitHub Release created"
}  # end if (-not $WindowsOnly) tag + release creation

# --- Upload artifacts --------------------------------------------------------
Step "Uploading artifacts"

if ((-not $SkipAndroid) -and (Test-Path $APK_DST)) {
    Write-Host "  Uploading APK..."
    $ErrorActionPreference = 'Continue'; gh release upload $TAG $APK_DST --repo $GITHUB_REPO --clobber; $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Fail "APK upload failed" }
    Ok "APK uploaded"
}

if ((-not $SkipAndroid) -and (Test-Path $AAB_DST)) {
    Write-Host "  Uploading AAB (Google Play)..."
    $ErrorActionPreference = 'Continue'; gh release upload $TAG $AAB_DST --repo $GITHUB_REPO --clobber; $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Warn "AAB upload failed (non-fatal)" } else { Ok "AAB uploaded" }
}

if ((-not $SkipWindows) -and (Test-Path $WIN_DST)) {
    Write-Host "  Uploading Windows ZIP..."
    $ErrorActionPreference = 'Continue'; gh release upload $TAG $WIN_DST --repo $GITHUB_REPO --clobber; $ec = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    if ($ec -ne 0) { Fail "Windows ZIP upload failed" }
    Ok "Windows ZIP uploaded"
}

# --- Upload to CN mirror (Vercel Blob CDN) -----------------------------------
Step "Uploading to CN mirror (Vercel Blob)"

# Prune old blobs first so we stay under the 1GB Hobby quota (keep only this version).
try {
    $pruneBody = @{ keep = $Version } | ConvertTo-Json
    $pruneResp = Invoke-RestMethod -Uri "$API_BASE/api/admin/mirror-cleanup" -Method POST `
        -Headers @{ 'x-upload-secret' = $CRON_SECRET } -ContentType 'application/json' -Body $pruneBody
    Ok "Blob prune: deleted $($pruneResp.deleted) old file(s)"
} catch {
    Warn "Blob prune failed (continuing): $_"
}

function Upload-ToCnMirror {
    param([string]$FilePath, [string]$Platform)

    $filename = Split-Path $FilePath -Leaf
    $mimeType = if ($Platform -eq 'android') {
        'application/vnd.android.package-archive'
    } else {
        'application/zip'
    }

    try {
        # Step 1: Request a client upload token from the portal
        $tokenBody = @{
            type    = "blob.generate-client-token"
            payload = @{
                pathname    = "apk/$filename"
                callbackUrl = "$API_BASE/api/admin/mirror-token"
                multipart   = $false
            }
        } | ConvertTo-Json -Depth 5

        $tokenResp = Invoke-RestMethod `
            -Uri "$API_BASE/api/admin/mirror-token" `
            -Method POST `
            -ContentType "application/json" `
            -Headers @{ "x-upload-secret" = $CRON_SECRET } `
            -Body $tokenBody

        if (-not $tokenResp.clientToken) {
            throw "No clientToken in response"
        }

        # Step 2: Upload directly to Vercel Blob CDN
        # URL: https://blob.vercel-storage.com/{pathname}
        $pathname  = "apk/$filename"
        $uploadUrl = "https://blob.vercel-storage.com/$pathname"
        $uploadHeaders = @{
            "Authorization" = "Bearer $($tokenResp.clientToken)"
            "Content-Type"  = $mimeType
            "x-mimeType"    = $mimeType
        }
        $uploadResp = Invoke-RestMethod `
            -Uri $uploadUrl `
            -Method PUT `
            -InFile $FilePath `
            -Headers $uploadHeaders

        $blobUrl = $uploadResp.url

        # Step 3: Register URL with portal (backup in case onUploadCompleted callback failed)
        $registerBody = @{
            token    = $CRON_SECRET
            platform = $Platform
            version  = $Version
            url      = $blobUrl
        } | ConvertTo-Json
        Invoke-RestMethod `
            -Uri "$API_BASE/api/admin/mirror-register" `
            -Method POST `
            -ContentType "application/json" `
            -Body $registerBody | Out-Null

        return $blobUrl
    } catch {
        throw $_
    }
}

if ((-not $SkipAndroid) -and (Test-Path $APK_DST)) {
    try {
        $cnApkUrl = Upload-ToCnMirror -FilePath $APK_DST -Platform "android"
        Ok "APK → CN mirror: $cnApkUrl"
    } catch {
        Warn "CN mirror upload failed: $_"
    }
}

if ((-not $SkipWindows) -and (Test-Path $WIN_DST)) {
    try {
        $cnWinUrl = Upload-ToCnMirror -FilePath $WIN_DST -Platform "windows"
        Ok "Windows → CN mirror: $cnWinUrl"
    } catch {
        Warn "CN mirror upload failed: $_"
    }
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
