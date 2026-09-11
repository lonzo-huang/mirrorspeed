# MirrorSpeed VPN — 客户端配置指南

## 快速开始

```bash
cd client
flutter pub get
flutter run -d <device>
```

构建时注入环境变量：
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=API_BASE=https://portal.mirrorspeed.com
```

---

## iOS / macOS 配置

见 [ios_macos_native/README.md](ios_macos_native/README.md)：两个 Packet Tunnel 扩展
（AmneziaWG / sing-box）已接入 `ios/`、`macos/` 工程，URL Scheme `mirrorspeed://` 已写入
Info.plist。Mac 上先 `bash ios_macos_native/build_apple_libs.sh` 构建 Go 库，再在
`ios_macos_native/Signing.xcconfig` 填 Team ID 即可签名运行。

---

## Android 配置

`android/app/src/main/AndroidManifest.xml` 已包含所有必要权限。

运行后系统会弹出 VPN 授权对话框，用户允许后即可建立隧道。

---

## Windows 配置

Windows 需要 WireGuard NT 驱动，`wireguard_flutter` 会自动调用 WireGuard 官方驱动。

首次运行需要管理员权限（安装驱动）。建议打包时使用 NSIS 安装器并申请提权。

```yaml
# pubspec.yaml 中 Windows 构建时可以启用以下
# (wireguard_flutter 会自动引入 wireguard-nt.dll)
```

---

## 打包发布

### Android APK
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=API_BASE=...
```

### iOS IPA
```bash
flutter build ipa --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=...
```

### Windows EXE
```bash
flutter build windows --release \
  --dart-define=...
```

---

## Supabase 配置

在 Supabase Dashboard → Authentication → URL Configuration 中添加：

**Redirect URLs（允许列表）：**
```
mirrorspeed://login-callback
```

**Site URL：**
```
https://portal.mirrorspeed.com
```
