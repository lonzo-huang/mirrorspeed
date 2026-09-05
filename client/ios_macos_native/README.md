# iOS / macOS 免费节点（sing-box / NetworkExtension）集成骨架

本目录是**只写骨架**：Windows 开发机无 Mac/Xcode，无法编译。你在 Mac 上按下面步骤
把这些源码接入 Xcode 工程，补齐 Libbox API 细节（标 `TODO` 处），即可编译测试。

## 🚀 快速开始（先看这段，2026-09 更新）

**Windows 侧已备好（你不用再弄的）：**
- `ios/` `macos/` Flutter 工程已用 `flutter create` 生成，bundle id `com.mirrorspeed.mirrorspeedVpn`。
- App Group / 扩展 bundle id 全部对齐为 `group.com.mirrorspeed.mirrorspeedVpn` / `…mirrorspeedVpn.PacketTunnel`。
- **entitlements 已预置**：`ios/Runner/Runner.entitlements`（NE + App Group）、
  `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements`（已加 NE + App Group + network client/server）。
- 插件 podspec（ios/macos）、`SingboxFlutterPlugin.swift`、隧道扩展骨架 `PacketTunnelProvider.swift` 都在。
- 优质节点（AmneziaWG）iOS 由 `amneziawg_flutter` 插件负责，**不需要 Libbox**。

**你在 Mac 上必须自己搞定的两个前置（缺了免费节点跑不起来）：**
1. **付费 Apple Developer 账号**（$99/年）——Network Extension + App Groups 的签名/描述文件必须它。
2. **Go + gomobile**——把 sing-box 编成 `Libbox.xcframework`（下面第一步）。

**推荐构建顺序（iOS 与 macOS 一起）：**
1. 先跑通 **优质节点**：`cd client && flutter pub get && cd ios && pod install`，
   Xcode 打开 `Runner.xcworkspace`，选真机，配好签名后 `flutter run` —— AmneziaWG 应能直接连
   （不涉及 NE 扩展，先验证 App 本体 + 登录 + 优质节点在 Apple 上 OK）。
2. 再做 **免费节点**：按下面「一～五」构建 Libbox、加 PacketTunnel 扩展、接骨架、补 TODO。
3. macOS 同理：`cd macos && pod install`，加一个 macOS 的 NE 扩展 target（同一份 Swift 源），
   注意 macOS 需 App Sandbox（entitlements 已配）。

遇到编译/签名报错，把 Xcode 的报错贴给我，我远程帮你改。

架构与 Android 一致：Flutter 侧完全复用 `lib/vpn/proxy_core_engine.dart`
（MethodChannel `mirrorspeed/singbox` + EventChannel `mirrorspeed/singbox/stage`），
无需改任何 Dart。Apple 平台由两块原生代码承担：

| 角色 | 文件 | 说明 |
|------|------|------|
| App 侧插件 | `packages/singbox_flutter/ios/Classes/SingboxFlutterPlugin.swift` | 注册通道；用 `NETunnelProviderManager` 装配/启停隧道；映射系统状态→stage |
| 隧道扩展 | `ios_macos_native/PacketTunnelProvider.swift` | **独立 NE target**，真正跑 libbox(sing-box)；实现 `openTun` |
| 权限 | `ios_macos_native/PacketTunnel.entitlements`、`Runner.entitlements.additions` | Network Extension + App Group |

> 插件的 podspec 已就绪（ios/macos 各一份，macOS 共用 iOS 的 Swift）。
> `packages/singbox_flutter/pubspec.yaml` 已声明 ios/macos 平台。

## 一、准备 Libbox.xcframework

sing-box 的 Apple 库需要自己从源码构建（不像 Android 有 JitPack）：

```bash
# 需 Go + gomobile
git clone https://github.com/SagerNet/sing-box
cd sing-box
make lib_install                       # 安装 gomobile
# 与 Android 侧 libbox 版本对齐（当前 1.13.x）
git checkout v1.13.x
./gomobile bind -v -target ios,iossimulator,macos \
  -tags 'with_gvisor,with_quic,with_utls,with_clash_api' \
  -o Libbox.xcframework ./experimental/libbox
```

把生成的 `Libbox.xcframework` 拖进 Xcode，同时链接到 **Runner** 与 **PacketTunnel** target
（Embed & Sign 到扩展，App 里 Do Not Embed 即可）。

## 二、新建 NetworkExtension 扩展 target

1. Xcode → File → New → Target → **Network Extension**（iOS）/ 同名（macOS）。
   - Bundle id：`com.mirrorspeed.mirrorspeedVpn.PacketTunnel`（须与
     `SingboxFlutterPlugin.kTunnelBundleId` 一致）。
   - Provider 类型：Packet Tunnel。
2. 删掉模板生成的 `PacketTunnelProvider.swift`，改为把本目录的
   `PacketTunnelProvider.swift` 加入该 target 的 Compile Sources。
   - macOS 用另一个扩展 target，但**同一份**源码即可加入两者。
3. 该 target 的 `Info.plist` 里 `NSExtension` → `NEProviderClasses` 指向
   `PacketTunnelProvider`（Xcode 模板通常已生成）。

## 三、Capabilities / entitlements

对 **Runner** 与 **PacketTunnel** 两个 target 都要开：
- **Network Extensions** → Packet Tunnel
- **App Groups** → `group.com.mirrorspeed.mirrorspeedVpn`

把 `PacketTunnel.entitlements` 用作扩展 target 的 entitlements；
把 `Runner.entitlements.additions` 里的键并入 Runner 现有 entitlements。
macOS 另需 App Sandbox + network client/server（见该文件注释）。

改 App Group / bundle id 时，三处保持一致：
`SingboxFlutterPlugin.kAppGroup`、`kTunnelBundleId`、`PacketTunnelProvider` 里的 group 名。

## 四、补齐 TODO

`PacketTunnelProvider.swift` 里标 `TODO(Libbox 版本)` 的地方，对照你构建出的
`Libbox` 头文件核对方法签名（`LibboxSetup` / `LibboxNewService` /
`LibboxTunOptionsProtocol` 的地址与 DNS 取法、平台接口其余成员）。不同版本略有差异。

## 五、构建

```bash
flutter pub get
cd ios && pod install    # 或 cd macos
flutter build ios        # 或 flutter build macos
```

真机需在 Apple Developer 后台为 App id 和扩展 id 都启用 Network Extensions + App Groups，
并生成对应 provisioning profile。

## 分应用代理说明

iOS 的 NEPacketTunnelProvider **不支持**按 App 分流（那是 Android `include_package` 专属）。
Dart 侧已把 `include_package` 限定仅 Android 注入，Apple 上走全局隧道，符合平台能力。
