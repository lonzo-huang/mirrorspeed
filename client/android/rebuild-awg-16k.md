# Rebuilding AmneziaWG native libs for 16 KB page size (Google Play / API 35)

## Why
Google Play rejects API-35 apps whose native `.so` are not 16 KB-aligned.
In our AAB only the **AmneziaWG** libs fail (Flutter's own libs are already fine):

| lib | align |
|---|---|
| libapp / libflutter / libdartjni / libdatastore | 16K / 64K ✅ |
| **libwg.so / libwg-go.so / libwg-quick.so** | **4K ❌** |

These three are **prebuilt** in `packages/amneziawg_flutter/android/src/main/jniLibs/`
(taken from AmneziaWG v2.0.0). Upstream 2.0.1 still ships 4K. The only fix is to
**rebuild them with NDK r28** (the r28 line defaults to `max-page-size=16384`).

ELF segment alignment is set at link time — no Gradle/packaging flag can fix a
prebuilt lib. (`useLegacyPackaging=false` + `debugSymbolLevel=FULL` are already set
in `app/build.gradle.kts`; they are prerequisites, not the fix.)

## Build (Linux or Docker — needs make/cmake; not Windows-native)
Run `rebuild-awg-16k.sh` on a Linux host (or in a container):

```bash
docker run --rm -v "$PWD:/work" debian:bookworm bash /work/rebuild-awg-16k.sh
```

It downloads NDK r28c + the upstream sources (tag 2.0.0, matching our bundled
`org.amnezia.awg` Kotlin/JNI), builds all 4 ABIs with `ANDROID_PACKAGE_NAME=
com.mirrorspeed.vpn`, and verifies every `.so` is ≥16 KB-aligned. Output lands in
`out/<abi>/{libwg.so,libwg-quick.so,libwg-go.so}`.

## Install + release
1. Copy `out/<abi>/*.so` over `packages/amneziawg_flutter/android/src/main/jniLibs/<abi>/`.
2. **Device-test the VPN** (Fast / Strong / Ultra modes must connect) — a miscompiled
   tunnel core can silently break connectivity; cannot be verified on the build host.
3. `./release.ps1 <next-version>` → new AAB passes the Play 16 KB check.
