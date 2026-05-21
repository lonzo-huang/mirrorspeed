#!/bin/bash
# MirrorSpeed VPN — iOS 一键 setup 脚本
# 运行前提：已在 client/ 目录执行过 flutter create . --project-name mirrorspeed_vpn
# 用法：bash setup-ios.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$SCRIPT_DIR/ios"
EXT_DIR="$SCRIPT_DIR/ios_extension"

# ── 检查 ios/ 目录是否存在 ────────────────────────────────────
if [ ! -d "$IOS_DIR" ]; then
  echo "❌ ios/ 目录不存在，请先运行："
  echo "   flutter create . --project-name mirrorspeed_vpn"
  exit 1
fi

echo "✅ 找到 ios/ 目录"

# ── 1. 复制 Network Extension 目录 ──────────────────────────
TUNNEL_DST="$IOS_DIR/MirrorSpeedTunnel"
mkdir -p "$TUNNEL_DST"
cp -v "$EXT_DIR/MirrorSpeedTunnel/PacketTunnelProvider.swift"       "$TUNNEL_DST/"
cp -v "$EXT_DIR/MirrorSpeedTunnel/Info.plist"                       "$TUNNEL_DST/"
cp -v "$EXT_DIR/MirrorSpeedTunnel/MirrorSpeedTunnel.entitlements"   "$TUNNEL_DST/"
echo "✅ Network Extension 文件已复制到 ios/MirrorSpeedTunnel/"

# ── 2. 复制主 App entitlements ───────────────────────────────
cp -v "$EXT_DIR/Runner.entitlements" "$IOS_DIR/Runner/Runner.entitlements"
echo "✅ Runner.entitlements 已复制到 ios/Runner/"

# ── 3. 修改 ios/Runner/Info.plist — 添加 URL Scheme ──────────
INFO_PLIST="$IOS_DIR/Runner/Info.plist"
if /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes" "$INFO_PLIST" &>/dev/null; then
  echo "⚠️  CFBundleURLTypes 已存在，跳过（请手动检查是否包含 mirrorspeed scheme）"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array"                              "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict"                             "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Editor"   "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array"         "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string mirrorspeed" "$INFO_PLIST"
  echo "✅ mirrorspeed:// URL Scheme 已写入 Info.plist"
fi

# ── 4. 添加 NSLocalNetworkUsageDescription ───────────────────
if /usr/libexec/PlistBuddy -c "Print :NSLocalNetworkUsageDescription" "$INFO_PLIST" &>/dev/null; then
  echo "⚠️  NSLocalNetworkUsageDescription 已存在，跳过"
else
  /usr/libexec/PlistBuddy -c \
    "Add :NSLocalNetworkUsageDescription string 'MirrorSpeed VPN 需要访问本地网络以建立 VPN 连接。'" \
    "$INFO_PLIST"
  echo "✅ NSLocalNetworkUsageDescription 已写入 Info.plist"
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  剩余步骤（需要在 Xcode 里手动完成，约 3 分钟）"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "1. 打开 Xcode："
echo "   open ios/Runner.xcworkspace"
echo ""
echo "2. File → New → Target → 搜索 'Network Extension' → 选择"
echo "   Product Name : MirrorSpeedTunnel"
echo "   Bundle ID    : com.mirrorspeed.vpn.network"
echo "   Language     : Swift"
echo ""
echo "3. 将 ios/MirrorSpeedTunnel/ 下的 3 个文件拖入新 Target"
echo "   （PacketTunnelProvider.swift / Info.plist / .entitlements）"
echo ""
echo "4. 新 Target → Signing & Capabilities："
echo "   → Add 'Network Extensions' → 勾选 Packet Tunnel Provider"
echo "   → Add 'App Groups'         → 填入 group.com.mirrorspeed.vpn"
echo ""
echo "5. Runner Target 同样添加上述两个 Capability"
echo ""
echo "6. 新 Target → Build Phases → Link Binary With Libraries："
echo "   添加 WireGuardKit（通过 Swift Package Manager 引入）"
echo "   URL: https://github.com/WireGuard/wireguard-apple"
echo "   Up to Next Major: 1.0.0"
echo ""
echo "完成后运行：make build-ios"
echo "═══════════════════════════════════════════════════════"
