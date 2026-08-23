# 开发记录 — 双引擎（sing-box 共享节点）与多平台铺开（v2.4.x）

> 归档时间：2026-08。覆盖「共享/免费节点」第二引擎的接入、分应用代理、Android
> 双进程隔离、APK 瘦身，以及 Windows / iOS / macOS 的桌面/移动多平台扩展。

## 1. 背景与目标

原客户端只有一条隧道：**优质节点**（AmneziaWG/WireGuard，固定 IP）。本阶段新增
**共享节点 / 免费节点**（社区机场清单，动态刷新），走 **sing-box（libbox）** 引擎，
与 AmneziaWG 平行。两条隧道系统级互斥，同一时刻只跑一条。

对外话术：`优质节点 · 固定IP` / `免费节点 · 动态刷新`。

## 2. 架构

```
                 首屏统一连接入口
                /                 \
   VpnProvider (AmneziaWG)     SharedNodeProvider (sing-box)
        |                              |
  amneziawg_flutter            singbox_flutter (自研插件)
   WireGuard 内核               libbox / VpnService(Android)
                                ProxyCoreEngine ── 平台感知 ──┐
                                                              │
                        Android: MethodChannel mirrorspeed/singbox
                        Windows: SingboxWindowsRunner (sing-box.exe 子进程)
                        iOS/macOS: NETunnelProviderManager → PacketTunnelProvider(libbox)
```

- 通道契约（三端一致）：MethodChannel `mirrorspeed/singbox`（init/start/stop/stage/
  transferRxTx）+ EventChannel `mirrorspeed/singbox/stage`。
- 启动参数：`SingboxConfig.build(node, ...)` 生成完整 sing-box JSON。

关键文件：
| 层 | 文件 |
|----|------|
| 共享节点状态 | `lib/providers/shared_node_provider.dart` |
| 引擎抽象（平台感知） | `lib/vpn/proxy_core_engine.dart` |
| sing-box 配置生成 | `lib/vpn/singbox_config.dart` |
| Windows 子进程运行器 | `lib/vpn/singbox_windows_runner.dart` |
| Android 原生插件 | `packages/singbox_flutter/android/.../SingboxVpnService.kt` |
| iOS/macOS 插件 | `packages/singbox_flutter/ios/Classes/SingboxFlutterPlugin.swift` |
| iOS/macOS 隧道扩展 | `ios_macos_native/PacketTunnelProvider.swift` |
| 免费节点国家分组 | `lib/utils/free_country.dart` |
| 分应用代理存储/界面 | `lib/services/app_proxy_store.dart` · `lib/screens/app_proxy_screen.dart` |

## 3. 关键问题与修复

### 3.1 Android 双进程隔离（切换引擎崩溃）
优质↔共享切换时程序闪退。根因：**两个 Go 运行时**（wireguard-go + libbox）跑在同一
进程里冲突。修复：把 sing-box 的 `VpnService` 放到独立进程
`android:process=":singbox"`，跨进程用 Intent 下命令、`sendBroadcast(ACTION_STAGE)`
回状态。已真机验证（Samsung S20 / Android 13 / arm64）。

### 3.2 分应用黑白名单对免费节点不生效
根因：`SingboxVpnService.openTun` 忽略了 libbox 传入的 `options.includePackage /
excludePackage`。修复：在 `openTun` 里遍历并 `addAllowedApplication /
addDisallowedApplication`。AmneziaWG 侧则在 `[Interface]` 后注入
`IncludedApplications / ExcludedApplications`（`VpnProvider._applyAppProxy`）。

**边界**：分应用仅在**智能模式**生效；**全局模式所有流量走隧道，不受黑白名单影响**。
`include_package` 是 Android 专属字段，桌面/Apple sing-box 不注入（走全局隧道）。

### 3.3 免费节点「连上但上不了外网」
TCP 可达 ≠ 代理可用（节点本身被 GFW 封）。修复：`SharedNodeProvider.connectSmart`
连上后经隧道实测 `gstatic.com/generate_204`，不通就按延迟依次换下一个（最多 6 个）。

### 3.4 时间归零仍可连接
`quotaExceeded` 之前被缓存、只在连接时 1s 定时器更新。修复：改为实时计算 +
常驻 `_ensureTrialTicker`。

### 3.5 APK 体积 93MB → 42MB
`libbox.so` 约 60MB（Go 二进制固有，已 strip）。旁加载包过大：`.so` 默认不压缩。
`android/app/build.gradle.kts` 设 `useLegacyPackaging = true`（压缩 .so）→ 42MB。
Google Play 走 AAB 按设备 ABI 分发，本就更小。

### 3.6 其它
- 节点名乱码：HTTP 响应用 `utf8.decode(res.bodyBytes)`（原 latin1）。
- 登录全挂：构建缺 `--dart-define`（SUPABASE_URL/ANON/API_BASE），用 `release.ps1` 注入。
- 浏览器不可选入黑白名单：`getInstalledApps(false, true)`（含系统 App）。
- 连播广告：`onAdDismissed` 加 3s 抑制，避免连续弹广告。

## 4. 多平台状态

| 平台 | 优质节点 | 免费节点(sing-box) | 状态 |
|------|---------|-------------------|------|
| Android | ✅ | ✅ 真机验证 | **已发布** |
| Windows | ✅（已有） | ✅ `SingboxWindowsRunner` | 待放入 `sing-box.exe`+`wintun.dll`（见 `windows/singbox/README.md`）后 `flutter build windows` |
| iOS | ✅（已有） | 🧩 骨架 | NEPacketTunnelProvider + libbox 骨架，待 Mac 编译（见 `ios_macos_native/README.md`） |
| macOS | — | 🧩 骨架 | 同 iOS，共用 Swift 源 |

### Windows 免费节点
`SingboxWindowsRunner` 用 `Process.start` 跑官方 `sing-box.exe`（自管 tun + wintun），
`ProxyCoreEngine` 在 `Platform.isWindows` 时委派给它。二进制不入库，
`windows/CMakeLists.txt` 构建时从 `windows/singbox/` 复制进包。创建 tun 需管理员权限。

### iOS / macOS
只写骨架（本机无 Mac）：插件 `SingboxFlutterPlugin.swift`（iOS/macOS 共用，`#if os()`
分平台）驱动 `NETunnelProviderManager`；扩展 `PacketTunnelProvider.swift` 跑 libbox、
实现 `openTun`（装配 `NEPacketTunnelNetworkSettings` + 抓 utun fd）。需在 Mac 上
用 gomobile 构建 `Libbox.xcframework`、建 NE target、开 App Group/Network Extension
capabilities，并对照 Libbox 头文件补齐 `TODO`。完整步骤见 `ios_macos_native/README.md`。

## 5. 发布

Android 走既有 `release.ps1 <version> -SkipWindows`（构建 arm64 单 APK + Play AAB，
打 tag、建 GitHub Release、刷新下载页缓存）。需环境变量 `MS_SUPABASE_ANON`
（构建注入的 Supabase anon key，不入库）。
