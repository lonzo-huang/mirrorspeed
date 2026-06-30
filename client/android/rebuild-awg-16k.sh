#!/usr/bin/env bash
# Rebuild AmneziaWG native libs (libwg.so / libwg-quick.so / libwg-go.so) with
# NDK r28c so the ELF LOAD segments are 16KB-aligned (Google Play API35 rule).
set -euxo pipefail

OUT="${OUT:-$(cd "$(dirname "$0")" && pwd)/out}"
mkdir -p "$OUT"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git cmake make patch xz-utils unzip file python3 \
  gcc g++ util-linux coreutils

cd /opt
# NDK r28c == SDK pkg 28.2.13676358 (matches host); r28 line defaults to 16KB pages.
if [ ! -d android-ndk-r28c ]; then
  curl -fL -o ndk.zip https://dl.google.com/android/repository/android-ndk-r28c-linux.zip
  unzip -q ndk.zip
fi
NDK=/opt/android-ndk-r28c
test -f "$NDK/build/cmake/android.toolchain.cmake"

# Match the version the plugin's bundled org.amnezia.awg Kotlin/JNI came from.
TAG=2.0.0
git clone --branch "$TAG" --recursive --depth 1 \
  https://github.com/amnezia-vpn/amneziawg-android.git /opt/src || \
git clone --branch 2.0.1 --recursive --depth 1 \
  https://github.com/amnezia-vpn/amneziawg-android.git /opt/src

cd /opt/src/tunnel/tools

build_abi() {
  local abi="$1" arch="$2" api="$3"
  local bdir="/tmp/b-$abi"
  rm -rf "$bdir"
  cmake -S . -B "$bdir" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM="android-$api" \
    -DANDROID_NATIVE_API_LEVEL="$api" \
    -DANDROID_ARCH_NAME="$arch" \
    -DANDROID_PACKAGE_NAME="com.mirrorspeed.vpn" \
    -DANDROID_HOST_PREBUILTS="$NDK/prebuilt/linux-x86_64" \
    -DGRADLE_USER_HOME=/root/.gradle \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$OUT/$abi" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
  cmake --build "$bdir" --target libwg.so libwg-quick.so libwg-go.so -j"$(nproc)"
}

build_abi arm64-v8a   arm64  24
build_abi armeabi-v7a arm    24
build_abi x86         x86    24
build_abi x86_64      x86_64 24

echo "=== alignment verification ==="
python3 - <<'PY'
import struct, glob, os, sys
bad=0
for f in sorted(glob.glob('/work/out/*/*.so')):
    d=open(f,'rb').read()
    phoff=struct.unpack_from('<Q',d,0x20)[0]; ent=struct.unpack_from('<H',d,0x36)[0]; n=struct.unpack_from('<H',d,0x38)[0]
    m=0
    for i in range(n):
        o=phoff+i*ent
        if struct.unpack_from('<I',d,o)[0]==1:  # PT_LOAD
            m=max(m,struct.unpack_from('<Q',d,o+0x30)[0])
    ok = m>=16384
    bad += 0 if ok else 1
    print(('OK ' if ok else 'BAD'), f'{m//1024:>3}K', f)
sys.exit(1 if bad else 0)
PY
echo "ALL_16K_OK"
ls -lR /work/out
