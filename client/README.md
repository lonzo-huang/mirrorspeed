# MirrorSpeed VPN — Flutter 客户端

> **平台**：Android / Windows / iOS（短期）  
> **当前版本**：**v2.3.0**（UI 全新设计 + 双模式节点选择 + 邮箱密码登录）  
> **技术栈**：Flutter 3.22+ · 自研混淆 UDP 隧道（AmneziaWG 内核）· HMAC 端口跳变 · WebSocket 中继（wstunnel）· Supabase · Provider · AdMob · in_app_purchase（规划中）

> ⚠️ **对外命名约定**：面向用户的服务名、目录、日志、二进制统一使用 **MirrorSpeed**，
> 不出现 `awg` / `amneziawg` 字样（隧道接口名为 `mirrorspeed`，Windows 服务为 `mirrorspeed_svc.exe`）。
> 本文档内部技术描述中仍以 AWG 指代底层内核。

---

## 目录

- [功能概览](#功能概览)
- [项目结构](#项目结构)
- [核心模块说明](#核心模块说明)
- [amneziawg\_flutter 插件](#amneziawg_flutter-插件)
- [构建与发布](#构建与发布)
- [环境配置](#环境配置)
- [常见问题](#常见问题)

---

## 功能概览

| 功能 | 说明 |
|------|------|
| 混淆 UDP 隧道 | 对抗 DPI 检测（Jc/Jmin/Jmax/S1/S2/H1-H4 参数）；v2.0.0 起 Windows 也支持 UDP 直连 |
| HMAC 端口跳变 | `port = 30000 + HMAC-SHA256(portSecret, UTC_hour) % 20000`，每小时变动，GFW 无法封锁固定端口；服务器开放 ±3 共 7 个端口窗口 |
| 会话端口锁定 | 仅在连接时计算端口，连上后不再随时间切换；前台恢复/网络变化由 `onAppResumed()` 自动重连 |
| WebSocket 中继自动回退 | 直连 12 秒内未连接，自动切换至 wstunnel WSS 443 中继模式 |
| 免费 / 付费双轨 | 免费用户每日免费**时长**（默认 30 分钟，服务端 `free_daily_seconds` 可配）；付费无限制无广告 |
| 按时间试用（v2.1+） | 首次连接起墙钟倒计时，断开继续走、次日重置，归零强制断开系统 VPN |
| AdMob 广告（v2.0.3+） | 开屏（可跳过）+ 激励视频；一次点击连播满 50 秒解锁 +30 分钟；会员屏蔽 |
| 双模式节点选择（v2.2） | 智能分配（延迟70%+负载30%评分）/ 手动列表（10 秒平均延迟、>300ms 截断、三档负载色块） |
| 三种登录（v2.2） | 邮箱验证码 / 邮箱密码 / Google SSO，登录页标签切换 |
| 全新 UI（v2.3） | 主页大圆环连接按钮 + 三栏数据 + 快捷宫格；开屏光环；毛玻璃底部导航；会员/设置/帮助页 |
| 多服务器节点 | 支持按延迟/负载切换多个 VPN 节点 |
| 智能路由 | 中国大陆 IP 直连，境外流量走 VPN（可切换） |

---

## 项目结构

```
client/
├── lib/
│   ├── main.dart                      # 入口，初始化 Supabase / Provider / Router
│   ├── models/
│   │   └── server_config.dart         # ServerConfig（含 portSecret 字段）/ DeviceInfo
│   ├── providers/
│   │   ├── auth_provider.dart         # 认证状态、设备信息、流量配额
│   │   └── vpn_provider.dart          # VPN 状态机（AWG直连 + wstunnel中继）
│   ├── services/
│   │   ├── port_hopping.dart          # HMAC 端口跳变计算
│   │   └── ws_relay_service.dart      # 纯 Dart UDP↔WebSocket 中继
│   ├── screens/
│   │   ├── splash_screen.dart         # 开屏（旋转光环 + 进度条）
│   │   ├── home_screen.dart           # 主页（大圆环连接按钮、三栏数据、节点卡、快捷宫格）
│   │   ├── server_list_screen.dart    # 节点列表（智能选择 + 延迟/三档负载）
│   │   ├── login_screen.dart          # 登录（验证码 / 密码 / Google 三标签）
│   │   ├── profile_screen.dart        # 「我的」（旧设计，按要求保留）
│   │   ├── vip_screen.dart            # 会员（方案 + 权益；购买为「敬请期待」占位，IAP 待接）
│   │   ├── settings_screen.dart       # 设置（协议/安全/通用分组）
│   │   ├── help_screen.dart           # 使用帮助（App 内 FAQ）
│   │   ├── sub_page.dart              # 二级页通用骨架（返回 + 标题）
│   │   ├── main_shell.dart            # 底部导航壳（毛玻璃，主页/我的）
│   │   └── ...
│   ├── theme.dart                     # 配色令牌（kBrand/kPanel/kAccentOn/kGold...）
│   ├── brand.dart                     # 双壳：Brand.appName / isZh / tr(zh,en)
│   └── env.dart                       # 常量（Supabase URL、iOS Bundle ID 等）
├── packages/
│   └── amneziawg_flutter/             # 自研 AWG Flutter 插件（见下节）
├── assets/
│   ├── images/
│   ├── lottie/
│   └── routes/cn_cidr.txt             # 中国大陆 IP 段（智能路由用）
├── android/                           # Android 原生层
├── windows/                           # Windows 原生层
├── ios_extension/
│   └── MirrorSpeedTunnel/
│       └── PacketTunnelProvider.swift # iOS Network Extension（AmneziaWireGuardKit）
├── pubspec.yaml                       # 依赖与版本
└── release.ps1                        # 一键构建 + 发布脚本
```

---

## 核心模块说明

### VpnProvider（`lib/providers/vpn_provider.dart`）

连接状态机，管理 AWG 直连与 WebSocket 中继的切换：

```
connect(server)
  │
  ├─ 计算 HMAC 端口并锁定到 _sessionPort（连上后不再变）
  ├─ 改写 wgConf Endpoint 端口
  ├─ 启动隧道（直连模式，接口名 mirrorspeed）
  ├─ 启动 12 秒回退计时器
  │
  ├─ [4 秒后] _postConnectCheck()
  │    ├─ 请求 https://connectivitycheck.gstatic.com/generate_204
  │    ├─ [204/200] → 取消计时器，直连保持
  │    └─ [失败]    → _switchToRelay(force: true)
  │
  └─ [12 秒超时] → _switchToRelay()
       ├─ 停止 AWG
       ├─ 启动 WsRelayService（本地 UDP ↔ wstunnel WSS 443）
       ├─ 改写 wgConf：
       │    Endpoint   = 127.0.0.1:<relayLocalPort>
       │    AllowedIPs = 0.0.0.0/0 排除 serverIp/32（防回环）
       └─ 重新启动隧道（走本地中继）
```

> **直连模式的 AllowedIPs 防回环（v2.0.0 关键）**：直连配置由 Portal 生成，已把
> **当前服务器自身公网 IP 的 /32** 从 AllowedIPs 中剔除（`allowedIpsExcluding()`）。
> 否则在 Windows（WinTun 无 socket protect）上，发往端点的隧道包会被再次路由进隧道，
> 形成 WG-in-WG 封装环路——握手成功但数据不通。多服务器/随时切换均适用：任意时刻只有
> 当前连接的那台服务器 IP 需要排除。Portal 还在 `[Interface]` 写入 `MTU = 1280` 避免满包被丢。

### PortHoppingService（`lib/services/port_hopping.dart`）

```dart
// 与服务器端 05-port-hopping.sh 完全一致的公式
int port = 30000 + HMAC-SHA256(portSecret, "YYYY-MM-DD HH")[0:4] % 20000;

// 尝试 current / current-1 / current+1 三个候选端口（容忍时钟偏差）
List<int> candidates = PortHoppingService.instance.candidatePorts(server.portSecret!);
```

### WsRelayService（`lib/services/ws_relay_service.dart`）

纯 Dart 实现的 UDP↔WebSocket 中继：

- 绑定本地随机 UDP 端口（供 AWG 连接）
- 与 wstunnel 服务器建立 WebSocket 连接
- 双向转发：AWG UDP 包 ↔ WebSocket 二进制帧

**WebSocket URL 格式：**
```
wss://{endpoint}/secure-tunnel/udp/127.0.0.1/{wgPort}
```

### AuthProvider（`lib/providers/auth_provider.dart`）

| 属性 | 类型 | 说明 |
|------|------|------|
| `isSuspended` | bool | 免费用户今日流量是否已用完 |
| `dailyQuotaBytes` | int? | 今日配额（null = 无限制，付费用户） |
| `dailyBytesUsed` | int | 今日已用字节数 |
| `usageRatio` | double | 已用比例 0.0–1.0 |

---

## amneziawg_flutter 插件

> 路径：`packages/amneziawg_flutter/`  
> 接口与 `wireguard_flutter` 完全兼容，直接替换即可。

### 平台支持

| 平台 | 实现 | 依赖 |
|------|------|------|
| Android | `org.amnezia.awg.backend.GoBackend` | `com.github.amnezia-vpn:amneziawg-android:1.0.0`（JitPack） |
| iOS | `NETunnelProviderManager` → `PacketTunnelProvider` | `AmneziaWireGuardKit`（CocoaPods） |
| Windows | Win32 SCM 服务管理 → `mirrorspeed_svc.exe`（用户态内核 + WinTun） | `mirrorspeed_svc.exe` + `wintun.dll`（见下）|

### 用法

```dart
// 初始化（app 启动时一次）—— 接口名对外统一为 mirrorspeed
await AmneziaWG.instance.initialize(interfaceName: 'mirrorspeed');

// 监听状态
AmneziaWG.instance.vpnStageSnapshot.listen((VpnStage stage) { ... });

// 连接
await AmneziaWG.instance.startVpn(
  serverAddress:            'vpn.example.com:PORT',
  wgQuickConfig:            awgConfigString,  // 包含 AWG 混淆字段
  providerBundleIdentifier: 'com.yourapp.tunnel',
);

// 断开
await AmneziaWG.instance.stopVpn();
```

### Windows 构建要求

`packages/amneziawg_flutter/windows/bin/` 下需要两个文件（已随仓库提交）：

```
mirrorspeed_svc.exe   # 隧道服务宿主（从 amneziawg-windows 改名编译，见该目录 BUILD.md）
wintun.dll            # WinTun 用户态 TUN 适配器（官方签名版）
```

在 Windows 上走用户态内核（amneziawg-go）+ WinTun，**不需要** `tunnel.dll`
或 WireGuard-NT 驱动（`wireguard.dll`）。CMakeLists.txt 通过 Flutter 的
`amneziawg_flutter_bundled_libraries` 约定，在打包时自动把它们装到 app .exe 旁边。
构建复现方法见 `packages/amneziawg_flutter/windows/bin/BUILD.md`。

**插件（`amneziawg_flutter_plugin.cpp`）的 Windows 关键实现：**

- 通过 SCM 注册名为 **MirrorSpeed VPN** 的服务，二进制 `mirrorspeed_svc.exe`，回退服务名 `mirrorspeed`
- 配置目录 `%TEMP%\mirrorspeed`，内核根目录 `C:\ProgramData\MirrorSpeed`（svc `main.go` 内 `PresetRootDirectory`）
- `ChangeServiceConfig2` 设 `SERVICE_SID_TYPE_UNRESTRICTED` —— WFP 过滤需要 service SID，否则报「组不存在」
- svc `main.go` 启动时 `redirectStdHandles` —— Go 服务无标准句柄会以 `ERROR_INVALID_HANDLE` 崩溃
- amneziawg-go `bind_windows.go` 打补丁：UDP 收包遇 `WSAECONNRESET/NETRESET/CONNREFUSED → goto retry`（go.mod replace），否则 ICMP 不可达会中断收包
- 内核诊断日志：ringlogger 写入 `C:\ProgramData\MirrorSpeed\log.bin`（二进制，svc 启动时可 dump）

**必须以管理员权限运行**：安装服务需要管理员。`windows/runner/runner.exe.manifest`
设 `requireAdministrator`，`windows/runner/CMakeLists.txt` 加 `/MANIFESTUAC:NO`
避免与 mt.exe 的 UAC 清单冲突（LNK1327）。若双击未弹 UAC（系统设置原因），
请右键「以管理员身份运行」。

---

## 构建与发布

### 前置要求

- Flutter SDK ≥ 3.22（路径：`C:\tools\flutter\bin`）
- Java（Android Studio JBR）：`C:\Program Files\Android\Android Studio\jbr`
- GitHub CLI (`gh`)，已登录
- 已在 `pubspec.yaml` 中更新版本号

### 一键发布（PowerShell）

```powershell
cd D:\projects\MirrorSpeed\client

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "C:\tools\flutter\bin;C:\Program Files\GitHub CLI\;" + $env:PATH

# 单一 APK + Windows ZIP（已合并 flavor；壳按设备语言运行时切换）
.\release.ps1 2.0.4

# 仅 Android
.\release.ps1 2.0.4 -SkipWindows

# 仅 Windows
.\release.ps1 2.0.4 -SkipAndroid
```

脚本自动完成：
1. `flutter clean && flutter pub get`
2. 构建**单个** Android APK（壳按语言运行时切换，详见「双壳架构」）
3. 构建 Windows ZIP（含 DLL 混淆重命名）
4. 打 Git Tag `v{version}` 并推送
5. 在 GitHub 创建 Release，上传 APK / ZIP
6. 上传到 CN 镜像（Vercel Blob CDN）
7. 调用 `/api/revalidate` 刷新下载页缓存

### DLL 混淆映射（Windows 构建）

| 原始文件 | 混淆后文件名 |
|---------|------------|
| `flutter_windows.dll` (19 字节) | `app_core_render.dll` (19 字节) |
| `amneziawg_flutter_plugin.dll` (28 字节) | `ms_network_security_core.dll` (28 字节) |
| `flutter_secure_storage_windows_plugin.dll` (41 字节) | `ms_secure_data_store_windows_plugin_x.dll` (41 字节) |

> 混淆在 PE 文件内同步修改 import table 字符串（等长替换，不改变 RVA），然后重命名文件。

### 手动构建

```powershell
# Android 直接下载包（仅 arm64-v8a，约 26MB，覆盖几乎所有现代手机）
flutter build apk --release --target-platform android-arm64

# Android Google Play 包（App Bundle，Play 按设备只下发对应架构）
flutter build appbundle --release

# Windows
flutter build windows --release --obfuscate --split-debug-info=build/debug_symbols/windows
```

> **包体积**：universal APK 会同时包含 arm64-v8a / armeabi-v7a / x86_64 三套原生库(~70MB)。
> 直接下载只打 **arm64-v8a**(~26MB);上架 Play 用 **.aab**,Play 自动按设备下发。

---

## 环境配置

客户端通过 `--dart-define` 注入运行时配置，硬编码在 `lib/env.dart`：

```dart
const String kSupabaseUrl    = String.fromEnvironment('SUPABASE_URL', ...);
const String kSupabaseAnon   = String.fromEnvironment('SUPABASE_ANON_KEY', ...);
const String kApiBase        = String.fromEnvironment('API_BASE', ...);
const String kProviderBundle = 'com.mirrorspeed.vpn.network';  // iOS Network Extension
```

---

## 常见问题

### 直连连不上，一直转圈

端口跳变可能未正确配置，检查：
1. 服务器 `cat /etc/wireguard/.port-secret` 是否有值
2. Portal API `/api/mobile/configs` 返回的 `port_secret` 是否与服务器一致
3. 12 秒后会自动切换 wstunnel 443 中继

### 中继模式无法连接

1. 服务器 `systemctl status wstunnel` 是否 running
2. Nginx `/secure-tunnel/` 路径配置是否正确（`wstunnel --restrict-to 127.0.0.1:51820`）
3. WSS 证书是否有效（443 端口）

### Android 连接失败：Permissions are not given

首次使用需在系统 VPN 授权对话框中点击"允许"，然后重新点击连接。

### Windows 提示缺少文件或隧道启动失败

确保 `mirrorspeed_svc.exe` 与 `wintun.dll` 在 app .exe 所在目录（构建时由
`windows/bin/` 自动打包）。若缺失，插件会返回「系统找不到指定的文件」，
客户端随后自动回退至 wstunnel 中继。其它常见情形：

- **提示「拒绝访问」**：未以管理员运行 → 右键「以管理员身份运行」。
- **服务约 10 秒后退出 / Event 7024**：通常是 svc 句柄或 service SID 问题，确认使用的是
  v2.0.0 的 `mirrorspeed_svc.exe`（含 redirectStdHandles + UNRESTRICTED SID）。
- **直连握手成功但打不开网页、随即切中继**：WG-in-WG 环路，需 Portal 已部署 AllowedIPs
  carve-out + MTU=1280（v2.0.0+），并**重新登录客户端**以拉取新配置。

### iOS Network Extension 无响应

1. Xcode 中 Network Extension target 需添加 `AmneziaWireGuardKit` pod
2. Bundle ID 须与 `env.dart` 中的 `kProviderBundle` 一致
3. entitlements 需包含 `com.apple.developer.networking.networkextension`

### 流量显示不更新

流量由 Vercel Cron（每分钟）同步，App 在每次 `connect()` 时拉取最新配额。可手动断开重连刷新。

---

## 双壳（Brand）架构 —— 单包按语言切壳（v2.0.4，重要）

> **给后续开发者 / AI 的背景**：本 App 是**单一安装包**，上架 Google Play 只用一个 listing，
> 以减少维护成本。原先的 `global` / `cn` 两个 flavor 已**合并**。

- **包名**：`com.mirrorspeed.vpn`（单一 applicationId；与旧的
  `com.mirrorspeed.mirrorspeed_vpn` / `com.mirrorspeed.jinsu` 都不同 → 旧包用户不会自动升级）。
- **壳由「运行时设备语言」决定**，不再用编译期 `--dart-define=APP_FLAVOR`：
  - 中文环境 → **镜速加速器**（合规：面向中文用户**不出现 "VPN" 字样**）
  - 其它语言 → **MirrorSpeed VPN**
- **启动器图标名称**：由 Android 资源限定符自动切换——
  `android/app/src/main/res/values/strings.xml`(=MirrorSpeed VPN) 与
  `res/values-zh/strings.xml`(=镜速加速器) 的 `app_name`；系统语言决定显示哪个，与代码无关。
- **App 内文案 / 功能开关**：统一走 `lib/brand.dart` 的 `Brand`（读 `PlatformDispatcher.locale`）：
  - `Brand.appName` — 产品名；`Brand.hideVpnWording` — 中文壳隐藏 VPN 字样；
    `Brand.showSmartRouting` — 中文壳特性（智能/全局路由切换）。
- **OAuth scheme**：单一 `mirrorspeed://login-callback`（Supabase 回调允许列表需包含它）。
- **未来两壳若分化**（不同特性/不同合规策略）：一切差异都集中到 `Brand` 用新增 getter 扩展，
  **不要**把 `Brand.isZh` 判断散落到各处，以便后续维护。

## 连接模式与状态（v2.0.1）

客户端按优先级自动尝试，三种模式对外名称（中文 / 其它语言）：

| 内部通道 | 对外名称（中文） | 对外名称（其它） | 触发 |
|---|---|---|---|
| 直连 UDP | 快速模式 | Fast Mode | 默认优先 |
| wstunnel 443 | 强力模式 | Strong Mode | 直连验证失败回退 |
| Cloudflare | 暴力模式 | Ultra Mode | 强力仍不通且配置了 cf_relay_url |

- **「连接中」直到验证流量畅通**：握手成功不等于能上网，必须 HTTP 204 探测通过后才显示「已连接」+模式。
- **手动断开即断开**：`disconnect()` 置 `_userInitiatedDisconnect`，挂起的探测/回退一律中止，绝不自动切下一模式。
- **路由零泄漏**：失败/退出/崩溃都会拆隧道清路由（见 2.0.0 修复 + 插件析构/构造清理）。

### 本地用量计量（#8，v2.0.1）

- **上限来自服务器**：`/api/mobile/configs` 下发 `daily_quota_bytes` → `AuthProvider.dailyQuotaBytes`
  → 通过 `VpnProvider.setDailyQuota()` 注入。付费用户为 null（无限，不计量）。
- **用量本地累计**：连接后每 5 秒调插件 `transfer()` 读隧道累计字节，求增量累加到
  `_dailyUsed`，持久化到 SharedPreferences，按 **UTC 日期**重置（与服务端每日额度对齐）。
- **平台实现**：Android 用 `GoBackend.getStatistics()`(totalRx+totalTx)；Windows 用
  `GetIfTable2` 读 `mirrorspeed` WinTun 适配器的 InOctets+OutOctets（直连/中继都走 WinTun，
  统计一致，且是解密后的内层字节=真实用量）；iOS 暂返回 -1（不计量）。
- **超额本地断开**：`_dailyUsed >= 上限` 即断开并标记 `quotaExceeded`，主页显示「已用完/升级」。

> **验证码长度**：客户端按 **6 位**实现（输满自动登录）。Supabase OTP 最短即 6 位，默认即可，无需特殊设置。

## 版本历史

| 版本 | 变更 |
|------|------|
| **2.3.0** | **UI 全新设计（参考设计师稿）**：开屏旋转光环；主页大圆环连接按钮（同心旋转光环）+ 延迟/时长/负载三栏 + 智能/全局切换 + 节点卡（智能/手动徽标）+ 快捷宫格；毛玻璃悬浮底部导航；新增**会员 / 设置 / 使用帮助**页面（`vip_screen` / `settings_screen` / `help_screen` / `sub_page`）；**「我的」页保留旧设计**。新增主题令牌 `kPanel/kAccentOn/kGold`。设计稿在 `D:\tmp\mirrorspeed ui`（React 代码，需 Flutter 重写）。**节点页/登录页完整还原待做**。 |
| **2.2.x** | **双模式节点选择**：智能分配（`pickAutoServer` 延迟70%+负载30%）+ 手动列表（`ServerConfig.addLatencySample` 10 秒滚动平均、>300ms 截断、`loadTier` 三档色块）；`/api/mobile/configs` 下发 `active_peers/load_percent`。**额度用尽禁止连接**（`connect()` 守卫 `_trialExceeded`）。**延迟测量修复**：改 ping `relayHost`（非 endpoint，修西班牙节点永久转圈）+ 持久 `http.Client` keep-alive + 预热丢首样本（修 30ms→250ms 虚高）。**广告连播**：`AdService` 预加载 3 条广告池 + `showRewardedChain` 一次点击连播满 50 秒。**三种登录**：加 `signInWithPassword/signUpWithPassword` + 三标签登录页。**品牌图标**：`flutter_launcher_icons` 替换 Flutter 默认图标为青绿盾牌（`assets/icon/`）。 |
| **2.1.x** | **三星修复**：额度归零时 `_forceStopOnQuota()` 无条件停原生隧道 + 中继（修「app 已断、系统 VPN 仍连」）；看广告需累计满秒数（`addAdWatch` 累加）才发放。**试用强杀不丢**：`_trialLoaded` 守卫修复启动竞态（`_rollTrialDayIfNeeded` 在 `_loadTrial` 前清零的 bug）+ 双写持久化（SharedPreferences + `path_provider` 文件 flush）。APK 改 `--split-per-abi` 单架构（修「软件包解析失败」）。 |
| **2.0.4** | **合并双 flavor 为单包**(`com.mirrorspeed.vpn`)上架 Google Play；壳按设备语言运行时切换(中文=镜速加速器/不显示 VPN；其它=MirrorSpeed VPN)；启动器名走 res/values(-zh)；`Brand` 抽象(`lib/brand.dart`)；单一 OAuth scheme `mirrorspeed`；release.ps1 改为单 APK。 |
| **2.0.3** | **接入 AdMob**：开屏广告(可跳过) + 激励视频(看完 +30 分钟试用)；**免费试用改为按时间**(首次连接起墙钟倒计时、断开不停、次日重置；上限 `app_config.free_daily_seconds` 从服务器拉取);minSdk≥23。 |
| **2.0.1** | **连接体验大改**：① Windows 窗口改为手机式窄宽度；② 去掉连接时长显示；③ 状态显示当前模式——快速模式(UDP)/强力模式(TCP 中继)/暴力模式(Cloudflare)，其它语言本地化；④ 手动断开即断开，不再自动切下一模式；⑤ 未确认流量畅通前一律显示「连接中」，验证通过才显示「已连接」+模式；⑥ 节点列表用延迟色点(绿<500/黄500-1500/红>1500)替代数值；⑦ 打开 App 直接进连接界面，登录改为「我的」里可选；⑧ **用量本地计量**——隧道适配器 rx+tx 本地累计、按 UTC 日重置、超额本地断开，上限从服务器拉取(Android=GoBackend 统计 / Windows=GetIfTable2 读 WinTun 适配器字节；iOS 暂返回 -1)；⑨ 验证码 6 位(Supabase 最低 6 位)、输满自动登录。适配器描述本地化需重编 `mirrorspeed_svc.exe`（见 BUILD.md，本版未做）。 |
| **2.0.0** | **正式支持 Windows UDP 直连**：Windows 用户态内核（`mirrorspeed_svc.exe`）+ WinTun；修复 WG-in-WG 环路（AllowedIPs 剔除服务器自身 /32）+ MTU=1280 + WSAECONNRESET 补丁 + service SID/句柄修复；全面去除对外 awg/amneziawg 命名（接口名 `mirrorspeed`，目录/日志 MirrorSpeed）；会话端口锁定 + `onAppResumed` 自动重连；端口窗口 ±3；provisioning 统一确定性命名 + 每服务器独立 api_secret + 唯一索引防重复 |
| 1.0.24 | **AWG + 端口跳变**：wireguard_flutter → amneziawg_flutter；HMAC 动态端口；iOS Network Extension 支持 |
| 1.0.22 | 修复 Android 图标渲染（关闭 Impeller，回退 Skia） |
| 1.0.18 | Windows DLL 混淆重命名；Supabase 注册触发器修复 |
| 1.0.6  | WebSocket 中继自动回退；免费流量配额显示 |
| 1.0.5  | 多服务器节点支持 |
| 1.0.4  | 初始公测版本 |
