# iOS / macOS 开发交接（macOS 环境）

> 目的：在 Mac 上继续 iOS/macOS 版开发。**大部分东西已在仓库里**，git clone/pull 即到。
> 本文件只补两类内容：① git 带不过去、必须手动准备的；② 本次会话新决策（晚于下面两份权威文档）。
>
> 权威参考（已在仓库，先读）：
> - 构建/运行/签名：[`client/ios_macos_native/README.md`](../ios_macos_native/README.md)
> - 架构与历史：[`client/docs/DEV-LOG-singbox-multiplatform.md`](./DEV-LOG-singbox-multiplatform.md)

## 0. 架构速记（三端共用 Dart；Apple 只需一个 NE 扩展）

> **⚠️ 重大简化（2026-10）**：客户端已统一到**纯 sing-box**（`refactor/unify-vpn-provider`
> 已并入 main，`amnezia_wg_engine.dart` 已删除）。优质节点也走 sing-box，**客户端不再用 AWG**。
> 所以 **Apple 侧只需要 `SingboxTunnel.appex` 一个扩展**；`ios_macos_native/AWGTunnel/`、
> `wggo/`、`packages/amneziawg_flutter` 对新客户端已不需要（可留作过渡参考，上架前清理）。

- Dart/Flutter 层与 Android/Windows **完全共用**。平台差异都在 `lib/vpn/singbox_config.dart`
  的 `_kIsApple` 分支里（见下）。`vpn_provider`（优质）与 `shared_node_provider`（免费）
  现在**共用同一个 sing-box 引擎**（`ProxyCoreEngine`）。
- 一个隧道、一个 NE 扩展：
  - **优质 + 免费** = sing-box/libbox → `SingboxTunnel.appex`（`packages/singbox_flutter`，bundle `<App>.PacketTunnel`）
- 通道契约三端一致：MethodChannel `mirrorspeed/singbox`（init/start/stop/stage/transferRxTx）
  + EventChannel `mirrorspeed/singbox/stage`。`transferRxTx` 在 Apple 由扩展
  `sendProviderMessage("stats")` 返回。

## 1. git 带不过去、必须手动准备（这才是真正要“传递”的）

1. **构建密钥**：`client/.release-secrets.local`（已 gitignore）。含
   `SUPABASE_URL / SUPABASE_ANON_KEY / API_BASE`，Makefile 的 `--dart-define` 要用。
   从 Windows 机拷到 Mac 的 `client/` 下即可（anon key 低敏，也可从任一 release 包提取）。
2. **Apple Developer 付费账号 + Team ID**：填进
   [`ios_macos_native/Signing.xcconfig`](../ios_macos_native/Signing.xcconfig) 的 `DEVELOPMENT_TEAM`。
   在 developer.apple.com 为 3 个 App ID 开启 **Network Extensions** 与 **App Groups**
   (`group.com.mirrorspeed.mirrorspeedVpn`)：
   - `com.mirrorspeed.mirrorspeedVpn`
   - `com.mirrorspeed.mirrorspeedVpn.AWGTunnel`
   - `com.mirrorspeed.mirrorspeedVpn.PacketTunnel`（= SingboxTunnel）
3. **工具链**：Xcode、Flutter（pubspec 要求 Dart SDK ≥ 3.3）、CocoaPods、Go ≥ 1.26
   (`brew install cocoapods go`)。iOS ≥ 15、macOS ≥ 13。
4. **AdMob iOS（上架前）**：Info.plist 的 `GADApplicationIdentifier` 目前用 Android 的
   App ID 占位（缺键 iOS 启动即崩）。上架前在 AdMob 建 iOS 应用换掉，并把广告位 ID 按平台分开。

## 2. 本次会话新决策（晚于上面文档，务必知晓）

- **分应用代理改为“仅智能模式生效”**（commit 7ffd92b）。Apple 本就不支持按 App 分流、
  入口隐藏、整机走隧道，所以 **Apple 无 UI 改动**；但「智能/全局」仍决定进隧道后怎么走
  （智能=airlane-cn 分流，全局=全代理），该开关随 config JSON 下发，原生无需改。
  参见记忆/`project_singbox_perapp_acl`。
- **IPv6 防泄漏**：tun 必须在有可用 v6 时声明 `::/0`，否则双栈站（ip.sb）走真实 v6 绕过隧道。
  Apple 走**实时探测**：`shared_node_provider._hasGlobalIpv6()` / `vpn_provider._tunIpv6()`
  已把 `ipv6` 传进 `SingboxConfig.build`。**Mac 上务必实测**：连上后开 ip.sb 确认 v6 不泄漏。
- **连接提速 singbox_only**：`api_service.dart:173` 的 ensurePeer 带 `singbox_only:true`
  跳过 AWG 下发——这是**免费/sing-box 路径**用的。Apple 的**优质节点走 AWG**，其 peer 另有
  ensure 路径，别让它被 singbox_only 跳过（Android 已正确区分，Apple 验证时留意一眼）。
- **发布说明/更新日志机制**：`client/release-notes/<版本>.md`（中英双语，`<!--LANG:zh-->` /
  `<!--LANG:en-->` 分段）是唯一来源，门户 `/download` 的「更新日志」会按语言渲染。
  `release.ps1` 只管 Windows/Android；**Apple 发版走 Makefile `build-macos/build-ipa` +
  `ios_macos_native/build_macos_dmg.sh` / TestFlight**。发 Apple 版时记得：① 同步 bump
  `pubspec.yaml` + `lib/version.dart`；② 写对应 `release-notes/<版本>.md`；③ 让 Apple 产物
  进入同一个 GitHub Release（客户端更新检测走 `/api/releases/latest`，与平台无关）。

## 3. 首次在 Mac 上跑（详见 ios_macos_native/README.md）

```bash
cd client
bash ios_macos_native/build_apple_libs.sh   # 首次 20~40 分钟（Libbox/WireGuardKitGo xcframework），之后跳过
flutter pub get
make run-macos                               # 或 make run-ios（真机，需签名）；会自动先跑 apple-libs 并带 dart-define
```

NE 是受限能力：**未签名/ad-hoc 能编译但连不上 VPN**，必须用上面的 Team ID 签名。
扩展日志：Console.app 过滤 `com.mirrorspeed.SingboxTunnel`。

## 4. 验证清单（真机/本机）

- [ ] 优质节点能连、能上网（现在也走 sing-box，连 Reality/hy2）。
- [ ] 免费节点能连、能上网。
- [ ] 智能模式：国内直连、海外走节点；全局模式：全部走节点。
- [ ] **分应用代理**：Apple 不支持按 App 分流 → 入口隐藏、整机走隧道（见 singbox_config `_kIsApple`）。
- [ ] **IPv6 不泄漏**（ip.sb 的 v6 栏显示节点地址或不支持，不是真实 v6）。
- [ ] 速率显示正常（transferRxTx 经 sendProviderMessage("stats") 回来）。
- [ ] 断开/重连稳定。

## 5. 待定/风险

- **macOS 分发方式**：当前是 App Store 式 app extension（sandbox）。若要 Developer ID 站外
  分发 DMG，需改成 **System Extension**（`packet-tunnel-provider-systemextension`），另议。
- **清理 AWG 残留**（可选）：客户端已纯 sing-box，`ios_macos_native/AWGTunnel/`、`wggo/`、
  `packages/amneziawg_flutter` 及 Xcode 里的 AWGTunnel target 对新客户端已无用，可在上架前移除，
  减小包体、少一个扩展要签。
- **AdMob iOS App ID / 广告位**（见 §1.4）。
