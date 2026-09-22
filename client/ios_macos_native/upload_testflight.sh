#!/bin/bash
# 打包 iOS 正式包并上传到 App Store Connect（TestFlight / 送审用）。
#
# 为什么不直接用 `flutter build ipa`：
#   Xcode 自动签名在「归档」阶段只能用开发证书，而开发描述文件要求团队里至少注册
#   一台 iPhone —— 没注册设备时直接签名失败。上架包本来就该用发布证书，所以这里：
#     1. 无签名归档
#     2. 手动用临时签名把 VPN 权限(NE / App Group)写进 App 和两个隧道扩展
#     3. 导出时由 Xcode 的云端发布证书重签（会保留第 2 步写入的权限）并直接上传
#   团队里注册过 iPhone 之后，标准的 `flutter build ipa` 也能用。
#
# 用法（在 client/ 下）：
#   bash ios_macos_native/upload_testflight.sh            # 构建号自动取当前时间(yymmddHHMM)，保证递增
#   bash ios_macos_native/upload_testflight.sh 95         # 指定构建号
#   bash ios_macos_native/upload_testflight.sh --no-upload  # 只打包导出到本地，不上传
set -euo pipefail

# flutter 可能不在非交互 shell 的 PATH 里（例如从 IDE/自动化里调用）。
# 不补这一句的话，第 1 步会以 "flutter: command not found" 失败，而调用方
# 若用管道取输出还会拿到 0 —— 看起来"上传成功"实则什么都没发生。
export PATH="$PATH:$HOME/development/flutter/bin"
command -v flutter >/dev/null || { echo "❌ 找不到 flutter，请检查 PATH"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$(cd "$HERE/.." && pwd)"
cd "$CLIENT"

UPLOAD=1
BUILD_NUMBER=""
for a in "$@"; do
  case "$a" in
    --no-upload) UPLOAD=0 ;;
    *) BUILD_NUMBER="$a" ;;
  esac
done
# 用时间戳做构建号：不改 pubspec(安卓 versionCode 不受影响)，且天然递增、不会撞号
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%y%m%d%H%M)}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$HERE/Signing.xcconfig" | tr -d '[:space:]')"
[[ -n "$TEAM" ]] || { echo "❌ ios_macos_native/Signing.xcconfig 里没填 DEVELOPMENT_TEAM"; exit 1; }

# 启动参数与 Makefile 保持一致（Supabase / API 地址）
eval "$(grep -E '^(SUPABASE_URL|SUPABASE_ANON|API_BASE) ' Makefile | sed -E 's/ *= */=/; s/^/export /')"

ARCHIVE="build/ios/archive/Runner.xcarchive"
OUT="build/ios/testflight"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▶ 1/5 生成 Flutter 配置（构建号 ${BUILD_NUMBER}）"
flutter build ios --config-only --release --build-number "$BUILD_NUMBER" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON" \
  --dart-define=API_BASE="$API_BASE" >/dev/null

echo "▶ 2/5 无签名归档（约 10 分钟）"
rm -rf "$ARCHIVE"
( cd ios && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "../$ARCHIVE" \
    archive CODE_SIGNING_ALLOWED=NO -quiet )

echo "▶ 3/5 写入 VPN 权限"
APP="$ARCHIVE/Products/Applications/Runner.app"
for f in "$APP"/Frameworks/*; do codesign -f -s - "$f" 2>/dev/null; done
codesign -f -s - --entitlements "$HERE/AWGTunnel/AWGTunnel-iOS.entitlements"         "$APP/PlugIns/AWGTunnel.appex"     2>/dev/null
codesign -f -s - --entitlements "$HERE/SingboxTunnel/SingboxTunnel-iOS.entitlements" "$APP/PlugIns/SingboxTunnel.appex" 2>/dev/null
codesign -f -s - --entitlements "ios/Runner/Runner.entitlements"                    "$APP"                             2>/dev/null

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
EOF

echo "▶ 4/5 发布证书重签并导出，检查权限"
rm -rf "$OUT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet
unzip -q -o "$OUT"/*.ipa -d "$WORK/ipa"
PAY="$(ls -d "$WORK"/ipa/Payload/*.app)"
for b in "$PAY" "$PAY/PlugIns/AWGTunnel.appex" "$PAY/PlugIns/SingboxTunnel.appex"; do
  if ! codesign -d --entitlements - --xml "$b" 2>/dev/null | grep -q "packet-tunnel-provider"; then
    echo "❌ $(basename "$b") 缺少 Network Extension 权限，VPN 会连不上 —— 中止上传"; exit 1
  fi
done
echo "   ✓ 三个包的 VPN 权限都在"

if [[ $UPLOAD == 0 ]]; then
  echo "✅ 已导出: ${OUT}（未上传）"; exit 0
fi

echo "▶ 5/5 上传到 App Store Connect"
sed 's#<string>export</string>#<string>upload</string>#' "$WORK/ExportOptions.plist" > "$WORK/Upload.plist"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/upload" \
  -exportOptionsPlist "$WORK/Upload.plist" -allowProvisioningUpdates -quiet
VER="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)"
echo "✅ 已上传 ${VER} (${BUILD_NUMBER})。苹果处理约 10~30 分钟后可在 TestFlight 安装。"
