#!/bin/bash
# 打 macOS 正式包并上传到 App Store Connect（Mac App Store 送审 / TestFlight for Mac）。
#
# 为什么走 Mac App Store 而不是站外 DMG：
#   macOS 上 NEPacketTunnelProvider 以 **app extension** 形式工作，主要面向 Mac App
#   Store 应用；站外分发（Developer ID + DMG）Apple 要求改成 **System Extension**
#   —— 那要换 target 类型、走 OSSystemExtensionRequest 申请安装、用户去系统设置点
#   允许，且开发签名的 sysex 还得关 SIP 才能加载。走 App Store 则现有结构直接可用。
#   实测旁证：本机 app-extension 的开发签名副本不被系统登记（pluginkit 查不到，
#   日志里连拒绝记录都没有），而同机从 Mac App Store 装的 sing-box 官方版正常。
#
# Mac App Store 的硬性要求（已在 entitlements 里满足）：
#   App 与扩展都必须启用 App Sandbox，并显式声明 network.client / network.server。
#
# 前置：Apple Developer 付费账号（VPN 应用还要求是 Organization 实体，见指南 5.4）、
#       Xcode 已登录该账号（证书与描述文件由 -allowProvisioningUpdates 自动获取）。
#
# 用法（在 client/ 下）：
#   bash ios_macos_native/upload_mac_appstore.sh              # 构建号自动取时间戳
#   bash ios_macos_native/upload_mac_appstore.sh 42           # 指定构建号
#   bash ios_macos_native/upload_mac_appstore.sh --no-upload  # 只导出到本地
set -euo pipefail

# 归档/导出失败时必须立刻中止：xcodebuild 的 ** ARCHIVE FAILED ** 不一定反映在退出码上
# （例如并发构建抢同一个 DerivedData 会报 disk I/O error），而调用方若把输出接到管道，
# 真实退出码还会被管道吞掉 —— 曾因此出现「显示上传成功、实际没打包」。
die() { echo "❌ $*"; exit 1; }

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
# 时间戳做构建号：天然递增、不与 iOS/安卓的版本号冲突
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%y%m%d%H%M)}"
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$HERE/Signing.xcconfig" | tr -d '[:space:]')"
[[ -n "$TEAM" ]] || { echo "❌ ios_macos_native/Signing.xcconfig 里没填 DEVELOPMENT_TEAM"; exit 1; }

eval "$(grep -E '^(SUPABASE_URL|SUPABASE_ANON|API_BASE) ' Makefile | sed -E 's/ *= */=/; s/^/export /')"

ARCHIVE="build/macos/archive/Runner.xcarchive"
OUT="build/macos/appstore"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▶ 1/4 生成 Flutter 配置（构建号 ${BUILD_NUMBER}）"
flutter build macos --config-only --release --build-number "$BUILD_NUMBER" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON" \
  --dart-define=API_BASE="$API_BASE" >/dev/null

echo "▶ 2/4 归档（自动签名，约 10 分钟）"
rm -rf "$ARCHIVE"
( cd macos && xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "../$ARCHIVE" \
    archive -allowProvisioningUpdates -quiet )

[[ -d "$ARCHIVE" ]] || die "归档失败，没有产出 $ARCHIVE（看上面的 xcodebuild 报错）"

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

echo "▶ 3/4 导出并校验"
rm -rf "$OUT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet

APP="$ARCHIVE/Products/Applications/mirrorspeed_vpn.app"
EXT="$APP/Contents/PlugIns/SingboxTunnel.appex"
# 这三项缺任何一个都会让隧道连不上或被 App Store 拒收，且都不会在构建期报错
for b in "$APP" "$EXT"; do
  codesign -d --entitlements - --xml "$b" 2>/dev/null | grep -q "packet-tunnel-provider" \
    || { echo "❌ $(basename "$b") 缺少 Network Extension 权限 —— 中止"; exit 1; }
  codesign -d --entitlements - --xml "$b" 2>/dev/null | grep -q "app-sandbox" \
    || { echo "❌ $(basename "$b") 未启用 App Sandbox（Mac App Store 必需）—— 中止"; exit 1; }
done
find "$EXT" -name "airlane-cn.srs" | grep -q . \
  || { echo "❌ 扩展里缺少规则集 airlane-cn.srs —— 中止"; exit 1; }
echo "   ✓ VPN 权限 / App Sandbox / 规则集 均已就位"

if [[ $UPLOAD == 0 ]]; then
  echo "✅ 已导出: ${OUT}（未上传）"; exit 0
fi

echo "▶ 4/4 上传到 App Store Connect"
sed 's#<string>export</string>#<string>upload</string>#' "$WORK/ExportOptions.plist" > "$WORK/Upload.plist"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/upload" \
  -exportOptionsPlist "$WORK/Upload.plist" -allowProvisioningUpdates -quiet
VER="$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml | tr -d '[:space:]')"
echo "✅ 已上传 macOS ${VER} (${BUILD_NUMBER})。苹果处理后可在 TestFlight / 版本页面选用。"
