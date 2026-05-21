# MirrorSpeed VPN — Flutter 客户端

> **平台**：Android / Windows  
> **技术栈**：Flutter 3.22+ · WireGuard · WebSocket 中继（wstunnel）· Supabase · Provider

---

## 目录

- [功能概览](#功能概览)
- [项目结构](#项目结构)
- [核心模块说明](#核心模块说明)
- [构建与发布](#构建与发布)
- [环境配置](#环境配置)
- [常见问题](#常见问题)

---

## 功能概览

| 功能 | 说明 |
|------|------|
| WireGuard VPN | 原生 WireGuard 隧道，使用 `wireguard_flutter` |
| WebSocket 中继自动回退 | WireGuard 12 秒内未连接，自动切换至 WSS 中继模式（绕过 GFW） |
| 免费 / 付费双轨 | 免费用户每日 500 MB（服务端可配置）；付费用户无限制 |
| 流量配额显示 | 主页进度条实时显示今日已用流量及剩余额度 |
| 多服务器节点 | 支持按延迟切换多个 VPN 节点 |
| 设备管理 | 每台设备独立密钥对，最多可注册多设备 |

---

## 项目结构

```
client/
├── lib/
│   ├── main.dart                    # 入口，初始化 Supabase / Provider / Router
│   ├── models/
│   │   └── server_config.dart       # VpnServer / DeviceInfo 数据模型（含流量配额字段）
│   ├── providers/
│   │   ├── auth_provider.dart       # 认证状态、设备信息、流量配额
│   │   └── vpn_provider.dart        # VPN 连接状态机（直连 + 中继双模式）
│   ├── services/
│   │   └── ws_relay_service.dart    # 纯 Dart UDP↔WebSocket 中继（WireGuard → wstunnel）
│   ├── screens/
│   │   ├── home_screen.dart         # 主页（连接按钮、节点卡、流量进度条、中继徽章）
│   │   ├── login_screen.dart        # 邮箱登录 / 注册
│   │   ├── devices_screen.dart      # 设备列表与管理
│   │   └── ...
│   └── router.dart                  # go_router 路由配置
├── assets/
│   ├── images/                      # 图片资源
│   └── lottie/                      # Lottie 动画
├── android/                         # Android 原生层（WireGuard 权限等）
├── windows/                         # Windows 原生层
├── pubspec.yaml                     # 依赖与版本
└── release.ps1                      # 一键构建 + 发布脚本
```

---

## 核心模块说明

### VpnProvider（`lib/providers/vpn_provider.dart`）

连接状态机，管理 WireGuard 直连与 WebSocket 中继的切换：

```
connect()
  │
  ├─ 启动 WireGuard（直连模式）
  ├─ 启动 12 秒回退计时器
  │
  ├─ [12 秒内 connected] → 取消计时器，保持直连
  │
  └─ [12 秒超时] → _switchToRelay()
       ├─ 停止 WireGuard
       ├─ 启动 WsRelayService（本地 UDP ↔ wstunnel WSS）
       ├─ 修改 WireGuard 配置：
       │    Endpoint = 127.0.0.1:<relayLocalPort>
       │    AllowedIPs = 10.200.0.0/24（仅 VPN 子网，防止路由回环）
       └─ 重新启动 WireGuard
```

**关键方法：**
- `connect(server)` — 发起连接
- `disconnect()` — 断开并清理中继
- `_switchToRelay(server)` — 切换到中继模式
- `_buildRelayConf(wgConf, relayPort)` — 构造中继模式的 WireGuard 配置

### WsRelayService（`lib/services/ws_relay_service.dart`）

纯 Dart 实现的 UDP↔WebSocket 中继：

- 绑定本地随机 UDP 端口（供 WireGuard 连接）
- 与 wstunnel 服务器建立 WebSocket 连接
- 双向转发：WireGuard UDP 包 → WebSocket 二进制帧，WebSocket 帧 → UDP 包

**WebSocket URL 格式：**
```
wss://{endpoint}/secure-tunnel/udp/127.0.0.1/{wgPort}
```

### AuthProvider（`lib/providers/auth_provider.dart`）

管理用户认证和设备配额状态：

| 属性 | 类型 | 说明 |
|------|------|------|
| `isSuspended` | bool | 免费用户今日流量是否已用完 |
| `dailyQuotaBytes` | int? | 今日配额（null = 无限制，付费用户） |
| `dailyBytesUsed` | int | 今日已用字节数 |
| `usageRatio` | double | 已用比例 0.0–1.0 |

### 主页 UI（`lib/screens/home_screen.dart`）

- **连接按钮**：正常状态显示"连接" / "断开"；配额用完时替换为"升级订阅"按钮
- **中继徽章**：橙色标签，中继切换中显示"切换 WebSocket 中继…"，已连接显示"WebSocket 中继"
- **流量进度条**（`_QuotaBar`）：仅免费用户可见，显示已用 / 总额度

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

# 仅 Android APK
.\release.ps1 1.0.7 -SkipWindows

# Android APK + Windows ZIP
.\release.ps1 1.0.7
```

脚本自动完成：
1. 构建 Android APK（`build\MirrorSpeed-{version}-android.apk`）
2. 构建 Windows ZIP（可选）
3. 打 Git Tag `v{version}` 并推送
4. 在 GitHub 创建 Release
5. 上传 APK / ZIP 产物
6. 调用 Vercel `/api/revalidate` 刷新下载页缓存

### 手动构建

```powershell
# Android
flutter build apk --release

# Windows
flutter build windows --release
```

---

## 环境配置

客户端通过 `lib/main.dart` 硬编码 Supabase 连接信息（公开 anon key，安全）：

```dart
await Supabase.initialize(
  url: 'https://your-project.supabase.co',
  anonKey: 'your-anon-key',
);
```

API 请求通过 Supabase Auth token 鉴权，无需额外配置。

---

## 常见问题

### 连接后无法上网

检查：
1. WireGuard `AllowedIPs` 是否包含 `0.0.0.0/0`（直连模式应包含）
2. 中继模式下 `AllowedIPs` 是否仅为 `10.200.0.0/24`（防路由回环）
3. 服务器端 WireGuard 是否在运行：`wg show wg0`

### 中继模式无法连接

检查：
1. 服务器 `wstunnel` 服务是否运行：`systemctl status wstunnel`
2. Nginx `/secure-tunnel/` 路径配置是否正确
3. WSS 证书是否有效（443 端口）

### 流量显示不更新

流量由 Vercel Cron（每分钟）同步，App 在每次 `connect()` 时拉取最新配额。可手动断开重连刷新。

### 免费用户无法连接（显示升级按钮）

用户今日配额已用完（`isSuspended = true`），次日 UTC 0 点自动恢复。  
升级付费订阅可立即解除限制。

---

## 版本历史

| 版本 | 变更 |
|------|------|
| 1.0.6 | WebSocket 中继自动回退；免费流量配额显示；修复下载页缓存 |
| 1.0.5 | 多服务器节点支持 |
| 1.0.4 | 初始公测版本 |
