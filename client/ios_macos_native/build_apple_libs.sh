#!/bin/bash
# 构建隧道扩展依赖的 Go 原生库（产物不入库，放 Frameworks/）：
#
#   Frameworks/Libbox.xcframework   sing-box（优质 + 免费节点）→ SingboxTunnel 扩展
#
# 纯 sing-box 客户端只需这一个库（原先还要编 amneziawg-go 给 AWGTunnel，已随 AWG 删除）。
#
# 依赖：Xcode、Go（>= 1.26）、git。用法：
#   bash build_apple_libs.sh            # 构建（已存在则跳过）
#   bash build_apple_libs.sh --force    # 强制重建
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
    libbox) WHAT="$a" ;;
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

case "$WHAT" in
  libbox|all) build_libbox ;;
  *) echo "未知目标: $WHAT（可用: libbox / all）"; exit 1 ;;
esac
