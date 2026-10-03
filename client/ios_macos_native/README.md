# iOS / macOS 原生部分（两个 Packet Tunnel 扩展）

Flutter/Dart 层与 Android、Windows **完全共用**；Apple 平台只多了这里的原生代码。

## 架构

```
Runner (Flutter App)
 ├─ amneziawg_flutter 插件 ──NETunnelProviderManager──▶ AWGTunnel.appex      优质节点
 │   packages/amneziawg_flutter/darwin                   amneziawg-go + WireGuardKit
 │                                                       bundle: <App>.AWGTunnel
 └─ singbox_flutter 插件  ──NETunnelProviderManager──▶ SingboxTunnel.appex  免费/共享节点
     packages/singbox_flutter/darwin                     libbox (sing-box 1.13.18)
                                                         bundle: <App>.PacketTunnel
```

- **为什么是两个扩展**：amneziawg-go 和 libbox 都是 Go 运行时，同一进程里只能有一个
  （Android 上同样的问题靠 `:singbox` 独立进程解决）。iOS/macOS 一个扩展就是一个进程，
  所以拆两个；系统同一时刻只允许一条 VPN，切换时会自动顶掉另一条。
- 两个插件按 `providerBundleIdentifier` 只认自己的 manager，不会串台。
- 通道契约与 Android 一致：`com.amneziawg.flutter/awgcontrol|awgstage`、
  `mirrorspeed/singbox` + `mirrorspeed/singbox/stage`。`transferRxTx` 经
  `sendProviderMessage("stats")` 由扩展返回（AWG 取 UAPI rx/tx，sing-box 取 utun 接口计数）。
- 扩展 bundle id 由主 App bundle id 推导（`+ .AWGTunnel` / `+ .PacketTunnel`），
  Dart 里的 `kProviderBundle` 已不再使用。

| 目录/文件 | 说明 |
|---|---|
| `AWGTunnel/` | 优质节点扩展：`PacketTunnelProvider.swift` + vendored WireGuardKit（取自 amneziawg-apple，MIT，见 `COPYING`） |
| `SingboxTunnel/` | 免费节点扩展：`PacketTunnelProvider.swift` + `SingboxPlatform.swift`（libbox 平台接口，参照 sing-box-for-apple） |
| `wggo/` | amneziawg-go 的 C 桥（`api-apple.go`），已去掉 xray 以控制 iOS 扩展 50MB 内存上限 |
| `build_apple_libs.sh` | 构建 `Frameworks/Libbox.xcframework`、`Frameworks/WireGuardKitGo.xcframework`（不入库） |
| `setup_xcode_targets.rb` | 把两个扩展 target 接进 `ios/`、`macos/` 的 Runner 工程（已执行并提交，一般无需再跑） |
| `Signing.xcconfig` | 填 Apple Developer Team ID，Runner 与两个扩展共用 |

## 在 Mac 上构建

前置：Xcode、Flutter、CocoaPods、Go ≥ 1.26（`brew install cocoapods go` 或官方安装包）。

```bash
cd client
bash ios_macos_native/build_apple_libs.sh     # 首次约 20~40 分钟（sing-box 较大），之后跳过
flutter pub get
flutter build macos                           # 或 make build-macos（带 dart-define）
flutter build ios --no-codesign               # 仅编译验证
```

`make build-ios / build-ipa / build-macos / run-ios / run-macos` 会自动先跑 `apple-libs`。

## 真机 / 本机运行 VPN（必须签名）

Network Extension 是受限能力，**未签名或 ad-hoc 签名的包能编译但连不上 VPN**。

1. 付费 Apple Developer 账号；把 Team ID 填进 `Signing.xcconfig` 的 `DEVELOPMENT_TEAM`。
2. developer.apple.com 为下面 3 个 App ID 开启 **Network Extensions** 与 **App Groups**
   （`group.com.mirrorspeed.mirrorspeedVpn`）。Xcode Automatic signing 通常会自动完成：
   - `com.mirrorspeed.mirrorspeedVpn`
   - `com.mirrorspeed.mirrorspeedVpn.AWGTunnel`
   - `com.mirrorspeed.mirrorspeedVpn.PacketTunnel`
3. `open ios/Runner.xcworkspace`（或 macos），确认三个 target 的 Signing 无报错，然后
   `make run-ios` / `make run-macos`。首次连接系统会弹「添加 VPN 配置」。
4. macOS 走 App Store 式 app extension（sandbox）。若将来要 Developer ID 站外分发，
   需改成 System Extension（`packet-tunnel-provider-systemextension`），另议。

调试扩展日志：Console.app 过滤 subsystem `com.mirrorspeed.AWGTunnel` / `com.mirrorspeed.SingboxTunnel`。

## 版本/兼容

- iOS ≥ 15.0；macOS ≥ 13.0（Go 1.27 运行时本身要求 macOS 13）。
- sing-box 版本与 Android 对齐（`LIBBOX_VERSION=v1.13.18`）。Go ≥ 1.26 构建 1.13.x 需
  `GOEXPERIMENT=nojsonv2`，脚本已处理。
- 升级 amneziawg-go：改 `wggo/go.mod` 后 `bash build_apple_libs.sh wggo --force`。

## 已知限制（Apple 平台能力所限）

- **分应用代理**：NEPacketTunnelProvider 不支持按 App 分流，Apple 上隐藏该入口、走全局隧道。
- **wstunnel/Cloudflare 中继兜底**：中继客户端跑在 App 进程里（`ws_relay_service.dart`），
  iOS 切到后台后 App 会被挂起，中继随之中断；直连（AmneziaWG UDP）不受影响。
- **广告**：Info.plist 的 `GADApplicationIdentifier` 暂用 Android 的 AdMob App ID 占位
  （缺这个键 iOS 启动即崩）。上架前在 AdMob 建 iOS 应用，替换 App ID，并把
  `lib/env.dart` 的广告位 ID 按平台区分。
