# iOS / macOS 开发现状总结

> **一句话现状（2026-10）**：Apple 端的代码**基本写完**（sing-box NE 扩展 + Flutter 插件 +
> Xcode target 接线 + 构建脚本都在仓库里），但**从未在真机 / 签名环境构建测试过**——
> 下一步是在 Mac 上 `build → 签名 → 真机验证 → TestFlight`。
>
> 配套文档：**怎么在 Mac 上做** 见 [HANDOFF-ios-macos.md](HANDOFF-ios-macos.md)；
> **构建/签名细节** 见 [../ios_macos_native/README.md](../ios_macos_native/README.md)。

## 状态矩阵

| 部分 | 状态 | 说明 |
|---|---|---|
| Dart/Flutter 业务层 | ✅ 共用 | 与 Android/Windows 同一套；Apple 差异都在 `singbox_config.dart` 的 `_kIsApple` 分支 |
| sing-box NE 扩展（Swift） | ✅ 代码完成 | `ios_macos_native/SingboxTunnel/`：`PacketTunnelProvider.swift` + `SingboxPlatform.swift`（libbox 平台接口），无 TODO/stub |
| Flutter 插件（darwin） | ✅ 代码完成 | `packages/singbox_flutter`（MethodChannel `mirrorspeed/singbox`） |
| Xcode target 接线 | ✅ 已提交 | `setup_xcode_targets.rb` 已执行，ios/macos 两个 `Runner.xcodeproj` 均含 PacketTunnel target |
| entitlements / App Group | ✅ 预置 | NE packet-tunnel + `group.com.mirrorspeed.mirrorspeedVpn`（iOS+macOS） |
| 构建脚本 | ✅ 就绪 | `build_apple_libs.sh`（Libbox.xcframework）、Makefile（run/build-ios/ipa/macos）、`build_macos_dmg.sh`、`upload_testflight.sh` |
| 规则集打包 | ✅ 就绪 | `ios_macos_native/RuleSets/*.srs`；Dart 用 `$RULESET_DIR` 占位符，扩展换成真实 bundle 路径 |
| **真机构建 + 签名** | ❌ 未做 | 需 Mac + 付费 Apple Developer + Team ID |
| **真机功能验证** | ❌ 未做 | 连通/分流/IPv6/速率/后台（见 HANDOFF §4） |
| AdMob iOS | ⚠️ 占位 | Info.plist 用 Android App ID 占位，上架前换 |
| AWG 残留清理 | ⬜ 可选 | 客户端已纯 sing-box，`AWGTunnel/`、`wggo/`、`packages/amneziawg_flutter` 不再需要 |
| macOS 分发方式 | ⬜ 待定 | App Store app-extension（现状）vs 站外 DMG（需 System Extension） |

## 架构（已随 2026-10 统一而简化）

客户端已统一到**纯 sing-box**（`amnezia_wg_engine.dart` 删除，`refactor/unify-vpn-provider`
并入 main）。优质 + 免费节点共用一个 sing-box 引擎（`ProxyCoreEngine`）。

- **Apple 只需一个 NE 扩展**：`SingboxTunnel.appex`（libbox），bundle `<App>.PacketTunnel`。
  → 之前规划的 `AWGTunnel.appex` 对新客户端**已不需要**。
- 通道契约三端一致：MethodChannel `mirrorspeed/singbox` + EventChannel `.../stage`；
  `transferRxTx` 在 Apple 由扩展 `sendProviderMessage("stats")` 返回。

## Apple 特有技术点（写代码/排障时注意）

- **TUN 协议栈用 `gvisor`**：NE 下系统栈不可用（`singbox_config.dart:183`）。
- **规则集随扩展打包**：Dart 下发的配置里是 `$RULESET_DIR/airlane-cn.srs` 占位符，
  扩展启动时替换成真实 bundle 路径（见 `PacketTunnelProvider.swift`）。
- **分应用代理不支持**：NEPacketTunnelProvider 无法按 App 分流 → Apple 隐藏该入口、整机走隧道。
- **IPv6 防泄漏**：按系统实时探测给 tun 声明 `::/0`（`_tunIpv6`/`_hasGlobalIpv6`）。
- **扩展内存上限**：iOS packet-tunnel 扩展 ~50MB，libbox 要控好（`build_apple_libs.sh` 已去冗余）。
- **版本**：iOS ≥ 15、macOS ≥ 13；libbox `v1.13.18`（与安卓对齐）；构建需 Go ≥ 1.26。

## 路线图（从现在到上架）

1. **M1 · macOS 本机跑通**：`build_apple_libs.sh` → `make run-macos`（签名）→ 连节点验证 sing-box 隧道通、能上网。Mac 上调试最快，先啃这个。
2. **M2 · iOS 真机**：`make run-ios` → 过 HANDOFF §4 验证清单（连通/分流/IPv6/速率/后台）。
3. **M3 · 上架准备**：建 AdMob iOS App ID 换占位；清理 AWG 残留（少签一个扩展、包更小）；定 macOS 分发方式。
4. **M4 · 分发**：iOS → TestFlight（`upload_testflight.sh`）→ App Store 审核；macOS → App Store 或（改 System Extension 后）Developer ID 签名 DMG。

## 已知限制 / 风险

- **NE 必须真签名**：未签名/ad-hoc 能编译但连不上 VPN。
- **证书/Team**：三个 App ID 需在 developer.apple.com 开 Network Extensions + App Groups。
- **macOS System Extension**：若要站外 DMG 分发，要从 app-extension 改成
  `packet-tunnel-provider-systemextension`，流程另议。
- **首次 `build_apple_libs.sh` 约 20~40 分钟**（编 Libbox.xcframework）。

## 关键指针

- 怎么做（Mac 上一步步）：[HANDOFF-ios-macos.md](HANDOFF-ios-macos.md)
- 构建/签名/分发细节：[../ios_macos_native/README.md](../ios_macos_native/README.md)
- sing-box 迁移设计背景：[../../docs/singbox-migration.md](../../docs/singbox-migration.md)
