#!/bin/bash
# 打 macOS 分发包（Developer ID 签名 + 公证 + DMG）。
#
# 与 Mac App Store 的区别：不走审核、自由分发，但必须用 Developer ID 证书签名并
# 经苹果公证（notarization），否则用户双击只会看到「已损坏，无法打开」。
#
# 前置条件（都只需办一次，需要你的开发者账号）：
#   1. Developer ID Application 证书
#        Xcode → Settings → Accounts → 选团队 → Manage Certificates → + →
#        Developer ID Application
#   2. 公证凭据（存进钥匙串，脚本按名字取用，不在命令行里出现密码）
#        xcrun notarytool store-credentials mirrorspeed \
#          --apple-id <你的 Apple ID> --team-id 957R34M9NR
#        （密码处填 App 专用密码，在 appleid.apple.com 生成）
#   3. 描述文件需带 Network Extensions 能力，否则隧道扩展加载不了
#
# 用法（在 client/ 下）：
#   bash ios_macos_native/build_macos_dmg.sh              # 构建+签名+公证+DMG
#   bash ios_macos_native/build_macos_dmg.sh --no-notarize  # 跳过公证（本机自测用）
set -euo pipefail

export PATH="$PATH:$HOME/development/flutter/bin"
command -v flutter >/dev/null || { echo "❌ 找不到 flutter"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$(cd "$HERE/.." && pwd)"
cd "$CLIENT"

NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$HERE/Signing.xcconfig" | tr -d '[:space:]')"
KEYCHAIN_PROFILE="mirrorspeed"
APP_NAME="MirrorSpeed VPN"
BUILT="build/macos/Build/Products/Release/mirrorspeed_vpn.app"
VER="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | tr -d '[:space:]')"
OUT="build/macos/dist"
DMG="$OUT/MirrorSpeed-$VER.dmg"

# Developer ID 证书必须存在，否则签出来的包别人打不开
ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
if [[ -z "$ID" ]]; then
  echo "❌ 找不到 Developer ID Application 证书。"
  echo "   Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application"
  exit 1
fi
echo "签名身份: $ID"

echo "▶ 1/5 构建 Release"
eval "$(grep -E '^(SUPABASE_URL|SUPABASE_ANON|API_BASE) ' Makefile | sed -E 's/ *= */=/; s/^/export /')"
flutter build macos --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON" \
  --dart-define=API_BASE="$API_BASE" >/dev/null

rm -rf "$OUT"; mkdir -p "$OUT"
APP="$OUT/$APP_NAME.app"
cp -R "$BUILT" "$APP"

echo "▶ 2/5 签名（由内向外，启用 Hardened Runtime）"
# 顺序很重要：必须先签嵌套内容，再签外层，否则外层签名会因内容变动而失效。
sign() { codesign --force --timestamp --options runtime --sign "$ID" "$@"; }

while IFS= read -r -d '' f; do sign "$f"; done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0 2>/dev/null)
while IFS= read -r -d '' f; do sign "$f"; done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -type f -print0 2>/dev/null)

sign --entitlements "$HERE/AWGTunnel/AWGTunnel-macOS.entitlements"         "$APP/Contents/PlugIns/AWGTunnel.appex"
sign --entitlements "$HERE/SingboxTunnel/SingboxTunnel-macOS.entitlements" "$APP/Contents/PlugIns/SingboxTunnel.appex"
sign --entitlements "macos/Runner/Release.entitlements"                    "$APP"

echo "   校验签名"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
# 三个包都必须带 VPN 权限，缺了用户连不上（iOS 侧踩过这个坑）
for b in "$APP" "$APP/Contents/PlugIns/AWGTunnel.appex" "$APP/Contents/PlugIns/SingboxTunnel.appex"; do
  codesign -d --entitlements - --xml "$b" 2>/dev/null | grep -q "packet-tunnel-provider" \
    || { echo "❌ $(basename "$b") 缺少 Network Extension 权限"; exit 1; }
done
echo "   ✓ 三个包的 VPN 权限都在"

echo "▶ 3/5 生成 DMG"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"     # 拖拽安装的目标
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [[ $NOTARIZE == 0 ]]; then
  echo "✅ 已生成（未公证，仅限本机）: $DMG"; exit 0
fi

echo "▶ 4/5 公证（苹果处理通常 1~5 分钟）"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "▶ 5/5 装订公证票据"
# 装订后用户离线也能通过 Gatekeeper 校验
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ 完成: $DMG"
echo "   版本 $VER，可直接上传到官网供用户下载。"
