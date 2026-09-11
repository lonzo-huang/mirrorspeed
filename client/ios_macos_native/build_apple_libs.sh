#!/bin/bash
# 构建 iOS/macOS 两个隧道扩展依赖的 Go 原生库（产物不入库，放 Frameworks/）：
#
#   Frameworks/Libbox.xcframework         sing-box（免费/共享节点）   → SingboxTunnel 扩展
#   Frameworks/WireGuardKitGo.xcframework amneziawg-go（优质节点）    → AWGTunnel 扩展
#
# 两者都是 Go 运行时，不能链接进同一进程（与 Android 双进程隔离同理），所以是两个扩展。
#
# 依赖：Xcode、Go（>= 1.26）、git。用法：
#   bash build_apple_libs.sh            # 两个都构建（已存在则跳过）
#   bash build_apple_libs.sh --force    # 强制重建
#   bash build_apple_libs.sh libbox|wggo
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/Frameworks"
WORK="${MS_APPLE_BUILD_DIR:-$HOME/.cache/mirrorspeed-apple}"
# 与 Android 侧 libbox 版本对齐（packages/singbox_flutter/android/build.gradle）
LIBBOX_VERSION="${LIBBOX_VERSION:-v1.13.18}"
IOS_MIN=15.0
# Go 1.27 运行时本身要求 macOS 13+
MACOS_MIN=13.0

FORCE=0
WHAT=all
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    libbox|wggo) WHAT="$a" ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

command -v go >/dev/null || { echo "❌ 需要 Go（https://go.dev/dl/）"; exit 1; }
mkdir -p "$OUT" "$WORK"

# ── sing-box Libbox.xcframework ─────────────────────────────────────────────
build_libbox() {
  local dst="$OUT/Libbox.xcframework"
  if [[ -d "$dst" && $FORCE == 0 ]]; then echo "✓ Libbox.xcframework 已存在（--force 重建）"; return; fi
  local src="$WORK/sing-box-$LIBBOX_VERSION"
  if [[ ! -d "$src" ]]; then
    git clone --depth 1 -b "$LIBBOX_VERSION" https://github.com/SagerNet/sing-box "$src"
  fi
  (
    cd "$src"
    export PATH="$(go env GOPATH)/bin:$PATH"
    make lib_install
    # Go >= 1.26 默认启用 encoding/json/v2，sing-box 1.13 依赖的 go-json-experiment
    # 旧版 alias.go 会编不过（undefined: json.SkipFunc），关掉该实验即可。
    export GOEXPERIMENT=nojsonv2
    # 官方构建脚本（tags 与 SFI 一致）；只要 iOS 真机 + 模拟器 + macOS。
    go run ./cmd/internal/build_libbox -target apple -platform ios,iossimulator,macos
  )
  rm -rf "$dst"
  mv "$src/Libbox.xcframework" "$dst"
  echo "✅ $dst"
}

# ── amneziawg-go → WireGuardKitGo.xcframework ───────────────────────────────
# 与 amneziawg-apple 的 Sources/WireGuardKitGo/Makefile 同法：c-archive + 打过
# boottime 补丁的 GOROOT（让计时器把设备休眠时间也算进去，否则握手定时器错乱）。
build_wggo() {
  local dst="$OUT/WireGuardKitGo.xcframework"
  if [[ -d "$dst" && $FORCE == 0 ]]; then echo "✓ WireGuardKitGo.xcframework 已存在（--force 重建）"; return; fi
  local b="$WORK/wggo"
  local goroot="$b/goroot"
  mkdir -p "$b"
  if [[ ! -f "$goroot/.prepared" || $FORCE == 1 ]]; then
    rsync -a --delete --exclude=pkg/obj/go-build "$(go env GOROOT)/" "$goroot/"
    patch -p1 -f -N -r- -d "$goroot" < "$HERE/wggo/goruntime-boottime-over-monotonic.diff"
    touch "$goroot/.prepared"
  fi

  # slice <输出名> <sdk> <GOOS> <GOARCH> <clang -target>
  slice() {
    local name=$1 sdk=$2 goos=$3 goarch=$4 target=$5
    local sysroot; sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
    local flags="-isysroot $sysroot -target $target"
    echo "  → $name"
    (
      cd "$HERE/wggo"
      GOROOT="$goroot" CGO_ENABLED=1 GOOS="$goos" GOARCH="$goarch" \
      CC="$(xcrun --sdk "$sdk" --find clang)" \
      CGO_CFLAGS="$flags" CGO_LDFLAGS="$flags" \
        "$goroot/bin/go" build -ldflags=-w -trimpath -buildmode c-archive -o "$b/$name.a" .
      rm -f "$b/$name.h"
    )
  }
  slice ios-arm64        iphoneos        ios    arm64 "arm64-apple-ios$IOS_MIN"
  slice sim-arm64        iphonesimulator ios    arm64 "arm64-apple-ios$IOS_MIN-simulator"
  slice sim-x86_64       iphonesimulator ios    amd64 "x86_64-apple-ios$IOS_MIN-simulator"
  slice macos-arm64      macosx          darwin arm64 "arm64-apple-macos$MACOS_MIN"
  slice macos-x86_64     macosx          darwin amd64 "x86_64-apple-macos$MACOS_MIN"

  mkdir -p "$b/ios" "$b/sim" "$b/macos"
  cp "$b/ios-arm64.a" "$b/ios/libwg-go.a"
  lipo -create -output "$b/sim/libwg-go.a"   "$b/sim-arm64.a"   "$b/sim-x86_64.a"
  lipo -create -output "$b/macos/libwg-go.a" "$b/macos-arm64.a" "$b/macos-x86_64.a"
  rm -rf "$dst"
  # 头文件不放进 xcframework：扩展的 bridging header 直接 include wggo/wireguard.h。
  xcodebuild -create-xcframework \
    -library "$b/ios/libwg-go.a" \
    -library "$b/sim/libwg-go.a" \
    -library "$b/macos/libwg-go.a" \
    -output "$dst"
  echo "✅ $dst"
}

case "$WHAT" in
  libbox) build_libbox ;;
  wggo)   build_wggo ;;
  all)    build_wggo; build_libbox ;;
esac
