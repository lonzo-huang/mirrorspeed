# MirrorSpeed VPN — 项目总览

> **技术栈**：自研混淆隧道内核（AmneziaWG 内核，对外以 MirrorSpeed 命名）· wstunnel · Nginx TLS 1.3 · FastAPI · Next.js 14 · Supabase · Stripe · Vercel · Flutter  
> **VPN 服务器系统**：Ubuntu 22.04 / 24.04 LTS  
> **客户端**：Android / Windows / iOS（Flutter 原生，自动 UDP 直连 → WebSocket 中继回退）  
> **当前版本**：客户端 **v2.0.0**（正式支持 Windows UDP 直连）

> ⚠️ **对外命名约定**：面向用户的一切（服务名、目录、日志、二进制）统一使用 **MirrorSpeed**，
> 不出现 `awg` / `amneziawg` 字样。AWG 仅作为内部内核技术在本文档中提及。

---

## 目录结构

```
MirrorSpeed/
├── client/              # Flutter 客户端（Android / Windows / iOS）
│   ├── lib/             #   Dart 源码
│   ├── packages/
│   │   └── amneziawg_flutter/  # 自研 AWG 插件（Android/iOS/Windows）
│   ├── android/         #   Android 原生层
│   ├── windows/         #   Windows 原生层
│   └── ios_extension/   #   iOS Network Extension（PacketTunnelProvider）
├── portal/              # Next.js 官网 + 管理后台（托管于 Vercel）
├── vpn/                 # VPN 服务器安装
│   ├── docker/          #   ├─ Docker Compose 安装（推荐）
│   │   ├── docker-compose.yml
│   │   ├── .env.example
│   │   ├── vpn/         #   │    AmneziaWG + wstunnel + vpn-api
│   │   └── nginx/       #   │    Nginx + Let's Encrypt
│   ├── install.sh       #   └─ Shell 脚本一键安装（裸机）
│   └── 0x-*.sh          #      分步安装脚本
├── scripts/             # 辅助脚本（注册服务器到 Portal 等）
└── README.md            # 本文件
```

---

## 1. 系统架构总览

```
用户手机 / PC（Flutter App）
  │
  ├─[直连] 混淆 UDP 隧道（动态端口跳变）─────────────────────┐
  │        端口 = 30000 + HMAC-SHA256(portSecret, UTC_hour) % 20000
  │        服务器同时开放 ±3 hour 共 7 个端口（WINDOW_RADIUS=3，容忍时钟偏差）
  │        客户端"会话锁定"：连上后端口不再变，除非主动重连
  │
  └─[回退] WSS 443 → Nginx /secure-tunnel/ → wstunnel 9.7 ──┤
                                                             ↓
                                                   AmneziaWG 服务器
                                                   接口: awg0 / 10.200.0.0/24
                                                   混淆参数: Jc/Jmin/Jmax/S1/S2/H1-H4
                                                             │
                                                   企业内网 / 公网出口

浏览器（用户注册 / 订阅 / 管理设备）
  │ HTTPS
  ▼
Vercel（Next.js Portal）
  │ Supabase Admin SDK
  ├──→ Supabase（用户 / 设备 / 订阅 / 流量数据）
  │ X-API-Secret
  └──→ VPN 服务器 FastAPI（vpn-api）
         ├─ 创建 / 删除 Peer（确定性命名 ms-<设备>-<服务器>）
         ├─ 查询 Peer 流量（awg show dump）
         └─ 暂停 / 恢复 Peer（AllowedIPs 清零）

  鉴权：每台服务器使用各自的 api_secret（存于 vpn_servers.api_secret），
        不再全局共用单个 VPN_API_SECRET（支持异构密钥的多服务器机群）。
```

---

## 2. 核心功能说明

### 2.1 免费 / 付费双轨制

| 用户类型 | 流量限制 | 连接节点数 |
|----------|---------|-----------|
| 免费用户 | 每日 500 MB（可调整） | 全部节点 |
| 付费订阅 | 无限制 | 全部节点 |

**调整免费额度**（无需重新部署）：
```sql
-- 在 Supabase SQL Editor 执行，立即生效
UPDATE public.app_config SET value = '1073741824' WHERE key = 'free_daily_bytes'; -- 1 GB
UPDATE public.app_config SET value = '524288000'  WHERE key = 'free_daily_bytes'; -- 500 MB（默认）
```

### 2.2 连接协议（默认 + 回退）

App 连接时自动选择最优方式：

1. **直连混淆 UDP 隧道**（HMAC 动态端口）— 延迟最低，优先使用  
   - 端口 = `30000 + HMAC-SHA256(portSecret, UTC_hour)[0:4] % 20000`  
   - 服务器同时监听 current ±3 共 7 个端口（`WINDOW_RADIUS=3`）  
   - 混淆参数（Jc/Jmin/Jmax/S1/S2/H1-H4）对 DPI 隐藏流量特征  
   - **会话端口锁定**：客户端仅在「连接时」计算端口，连上后保持不变；切换网络/恢复前台时由 `onAppResumed()` 自动重连  
2. **WebSocket 中继**（WSS 443 → wstunnel）— 12 秒内未连接自动切换，绕过 GFW 封锁

切换后 App 主页显示橙色"WebSocket 中继"徽章。

### 2.3 Cron 自动化

Vercel Cron 调用 `/api/cron/sync-servers`，自动完成：
- 同步每台服务器 CPU / 内存 / 带宽 / 延迟状态
- 更新每个 Peer 的今日已用流量（`awg show dump`）
- 超额免费用户：自动暂停 Peer（断开连接）
- 次日 UTC 0 点：自动恢复 Peer

> ⚠️ **频率限制**：Vercel **Hobby 套餐只允许每日一次 cron**，因此 `sync-servers`
> 已降级为每日 `0 0 * * *`（见 `portal/vercel.json`）。如需更高频的状态/流量同步，
> 需升级 Vercel 套餐后改回 `* * * * *`，或用外部定时器带 `CRON_SECRET` 调用该端点。
> cron 内所有对服务器的调用均使用各服务器自己的 `api_secret`。

---

## 3. 快速部署

### 3.1 VPN 服务器

**方式一：Docker Compose（推荐，适合快速复制部署）**

```bash
# 1. 上传 docker 目录到服务器
scp -r vpn/docker/ root@<SERVER_IP>:/opt/mirrorspeed-docker/

# 2. SSH 到服务器
ssh root@<SERVER_IP>
cd /opt/mirrorspeed-docker

# 3. 配置并启动
cp .env.example .env && nano .env   # 填写 DOMAIN / EMAIL / VPN_API_SECRET
docker compose up -d

# 4. 获取服务端公钥
docker compose logs vpn | grep -A2 "server public key"
```

**方式二：Shell 脚本（裸机，适合深度定制）**

```bash
# 1. 上传脚本到服务器
scp -r vpn/ root@<SERVER_IP>:/opt/mirrorspeed/

# 2. SSH 到服务器，一键安装
DOMAIN="vpn.yourdomain.com" \
EMAIL="admin@yourdomain.com" \
VPN_API_SECRET="<同所有服务器的密钥>" \
bash /opt/mirrorspeed/install.sh
```

安装完成后记录输出的 **AmneziaWG 服务端公钥**，注册服务器时需要。

**裸机安装后查看端口跳变 secret：**
```bash
cat /etc/wireguard/.port-secret
```

### 3.2 Supabase 数据库

在 [Supabase Dashboard](https://supabase.com/dashboard) → SQL Editor 依次执行：

```
portal/supabase/migrations/001_schema.sql         # 基础表结构
portal/supabase/migrations/002_rls.sql            # 行级安全策略
portal/supabase/migrations/003_servers.sql        # 多服务器支持
portal/supabase/migrations/004_free_quota.sql     # 免费流量额度追踪
portal/supabase/migrations/009_fix_new_user_trigger.sql  # 修复注册触发器
portal/supabase/migrations/012_vpn_servers_api_secret.sql  # 每服务器独立 api_secret 列
portal/supabase/migrations/013_vpn_device_peers_unique.sql # (device,server) 唯一索引，防并发重复 peer
```

> **关于 012 / 013（本周新增，必须执行）**：
> - `012` 给 `vpn_servers` 增加 `api_secret` 列。所有 provisioning / cron 路径现在
>   读取**每台服务器自己的** `api_secret`（不再依赖全局 `VPN_API_SECRET` 环境变量）。
>   执行后需为每台服务器写入其密钥：
>   ```sql
>   UPDATE public.vpn_servers SET api_secret = '<该服务器 .env 里的 VPN_API_SECRET>' WHERE name = 'ES01';
>   ```
> - `013` 建立部分唯一索引 `(device_id, server_id) WHERE is_active`，从数据库层杜绝
>   并发 provisioning 产生重复 peer。第二个并发插入返回 `23505`，各路径已捕获并视为
>   「已存在、复用」。**执行前需先清理历史重复活跃 peer，否则建索引会失败。**

### 3.3 Portal（Vercel）

```bash
# 设置环境变量
vercel env add NEXT_PUBLIC_SUPABASE_URL      production
vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production
vercel env add SUPABASE_SERVICE_ROLE_KEY     production
vercel env add VPN_API_SECRET                production
vercel env add APP_ENCRYPTION_SECRET         production
vercel env add CRON_SECRET                   production
vercel env add GITHUB_TOKEN                  production  # 私有仓库下载用
vercel env add GITHUB_REPO                   production  # 格式: owner/repo

# 从项目根目录部署
vercel --prod --yes
```

### 3.4 注册服务器到 Portal

```sql
-- 在 Supabase SQL Editor 执行
INSERT INTO public.vpn_servers (
  name, display_name, location, country_code, flag_emoji,
  endpoint, port, public_key, api_url, api_secret, port_secret, sort_order
) VALUES (
  'ES01', '西班牙 01', 'Spain', 'ES', '🇪🇸',
  'spain01.yourdomain.com', 51820,
  '<服务端公钥>',
  'https://spain01.yourdomain.com/vpn-api',
  '<该服务器 .env 的 VPN_API_SECRET>',
  '<cat /etc/wireguard/.port-secret 的输出>',
  1
);
```

> - `api_secret`：该服务器 vpn-api 的鉴权密钥，**每台独立**，必须与服务器 `.env` 一致。
> - `port_secret`：由 Portal API 下发给客户端，客户端用它计算 HMAC 动态端口。
> - `api_url` 必须指向有 TLS 的域名，且 Nginx 已配置 `/vpn-api/` location（见故障排查）。

---

## 4. Flutter 客户端发布

```powershell
# 在 client/ 目录下，更新 pubspec.yaml 版本号后执行：
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "C:\tools\flutter\bin;C:\Program Files\GitHub CLI\;" + $env:PATH

# 仅 Android
.\release.ps1 2.0.0 -SkipWindows

# Android + Windows
.\release.ps1 2.0.0
```

脚本自动完成：构建 APK / ZIP → 打 Git Tag → 创建 GitHub Release → 上传产物 → CN 镜像。

---

## 5. 关键环境变量速查

| 变量名 | 用途 | 位置 |
|--------|------|------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 项目 URL | Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase 匿名密钥 | Vercel |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase 管理员密钥 | Vercel |
| `VPN_API_SECRET` | VPN 服务器 API 鉴权（**已弃用为全局共用**，现读 `vpn_servers.api_secret`，每台独立；仅旧代码/裸机 `.env` 仍引用） | 每台 VPN 服务器 `.env` + DB `vpn_servers.api_secret` |
| `APP_ENCRYPTION_SECRET` | AWG 私钥加密密钥 | Vercel |
| `CRON_SECRET` | Vercel Cron 鉴权 | Vercel + `client/release.ps1` |
| `GITHUB_TOKEN` | 私有仓库 Release 下载 | Vercel |
| `GITHUB_REPO` | 仓库路径（`owner/repo`） | Vercel |

---

## 6. 日常运维

### 查看服务器状态
```bash
# 服务器上执行
systemctl status nginx awg-quick@awg0 wstunnel nftables vpn-api

# 查看活跃 VPN 连接
awg show awg0

# 查看当前动态端口（端口跳变）
bash /opt/mirrorspeed/vpn/08-port-hopping-setup.sh status
```

### 手动触发流量同步 / 额度检查
```bash
curl -H "Authorization: Bearer <CRON_SECRET>" \
  https://www.mirrorspeed.com/api/cron/sync-servers
```

### 添加 / 删除用户设备
用户在 App 或 Portal 管理，管理员可在 Supabase Dashboard 直接操作 `vpn_devices` 表。

### 订阅管理
通过 Stripe Dashboard 管理，Portal 通过 Webhook 自动同步到 `subscriptions` 表。

---

## 7. 故障排查速查

| 症状 | 检查点 |
|------|--------|
| App 直连不上 | 端口跳变是否正常：`bash 05-port-hopping.sh status`；nftables DNAT 规则是否存在 |
| App 中继也连不上 | `systemctl status wstunnel`；Nginx `/secure-tunnel/` 路径配置；WSS 证书有效性 |
| 显示 0 个节点 | `vpn_device_peers` 是否有记录；`vpn-api /peers` 是否正常 |
| Windows 直连握手成功但无法上网 | 确认 Portal 已部署 AllowedIPs carve-out + MTU=1280（v2.0.0+）；客户端需重新登录拉取新配置 |
| provisioning 返回 403 invalid api secret | `vpn_servers.api_secret` 是否与该服务器 `.env` 的 `VPN_API_SECRET` 一致（迁移 012）|
| provisioning 返回 500 building peer | 服务器 `06-peer-manager.sh` 是否指向 `/etc/amnezia/amneziawg/awg0.conf` |
| vpn-api 404 | Nginx `sites-enabled` 实际加载的 server 块是否含 `/vpn-api/` location（注意 sites-available 与 sites-enabled 可能是独立文件而非软链） |
| 出现重复 peer / 共用 IP | 是否已执行迁移 013（唯一索引）|
| 流量不同步 | Vercel Cron 是否启用；`awg show awg0` dump 是否返回数据 |
| 下载页版本不更新 | `GITHUB_TOKEN` 是否配置；`/api/releases/latest` 是否返回 200 |
| 付费用户被限速 | `subscriptions` 表 `status` 是否为 `active` |

---

## 8. 技术架构详解

### AmneziaWG 配置生成流程

```
用户登录 → 注册设备（vpn_devices）
  → Portal 调用每台 VPN 服务器 vpn-api POST /peers
  → 服务器生成密钥对，写入 awg0.conf（含 AWG 混淆参数）
  → Portal 将加密私钥存入 vpn_device_peers
  → App 调用 GET /api/mobile/configs
  → Portal 解密私钥，生成 wg_conf 字符串（AWG Quick 格式）
  → Portal 同时返回 port_secret（HMAC 端口跳变密钥）
  → App 用 amneziawg_flutter 建立 VPN 隧道
```

### 端口跳变机制

```
服务器（08-port-hopping-setup.sh + awg-port-rotate.sh，每小时 cron）：
  port = 30000 + HMAC-SHA256(PORT_SECRET, "YYYY-MM-DD HH")[0:4] % 20000
  iptables DNAT：UDP port → 51820
  WINDOW_RADIUS=3 → 维护 current ±3 共 7 个相邻 hour 窗口端口（容忍较大时钟偏差）

客户端（port_hopping.dart + vpn_provider.dart）：
  同公式，计算 current ±N 候选端口
  连接时锁定所选端口（_sessionPort），连上后不再随时间切换
  首次连通性验证失败则 fallback → wstunnel 443
```

### 流量计量流程

```
Vercel Cron (Hobby 套餐每日一次；高频需升级套餐或外部定时器)
  → 调用 vpn-api GET /peers（用该服务器自己的 api_secret，含 rx_bytes + tx_bytes）
  → 计算增量（处理 AWG 重启归零）
  → 更新 vpn_device_peers.daily_bytes
  → 超过 app_config.free_daily_bytes → PATCH /peers/{name}/status {active: false}
  → 次日 UTC 0 点 → PATCH /peers/{name}/status {active: true}，重置计数器
```

### 客户端插件架构（packages/amneziawg_flutter）

```
AmneziaWG.instance（Dart）
  │
  ├─ Android: org.amnezia.awg.backend.GoBackend（JitPack）
  │            原生解析 AWG 混淆参数（Jc/Jmin/Jmax/S1/S2/H1-H4）
  │
  ├─ iOS:     NETunnelProviderManager → PacketTunnelProvider
  │            import AmneziaWireGuardKit（CocoaPods）
  │
  └─ Windows: Win32 服务管理（SCM）→ mirrorspeed_svc.exe（用户态内核 + WinTun）
               仅需 mirrorspeed_svc.exe + wintun.dll（不需 WireGuard-NT 驱动）
               服务以 MirrorSpeed VPN 注册，SID 类型 UNRESTRICTED（WFP 需要）
               配置/日志目录：%TEMP%\mirrorspeed、C:\ProgramData\MirrorSpeed
               必须以管理员权限运行（runner 清单 requireAdministrator）
```

### Windows 直连关键修复（v2.0.0）

Windows 上「能握手但下载不动、随即回退中继」的根因与修复（全部已落地）：

| 问题 | 根因 | 修复 |
|------|------|------|
| WG-in-WG 封装环路 | `AllowedIPs` 覆盖了服务器自身公网 IP，发往端点的隧道包又被路由回隧道（Windows WinTun 无 socket protect()，wireguard-windows 仅对字面 `0.0.0.0/0` 自动排除端点） | `portal/src/lib/wireguard.ts` 的 `allowedIpsExcluding()` 把**当前服务器的 /32** 从拆分后的 AllowedIPs 中精确剔除；`configs` 路由按 DNS 解析每台 endpoint 的 IP 后传入 `serverPublicIp`。**天然按服务器逐一生效，多服务器/随时切换均适用**（任意时刻只有当前端点需要排除）。 |
| 数据包静默丢弃 | userspace 内核默认 MTU ~1420，满包超过受限路径 MTU（PPPoE/移动网） | `generateWgConf` 在 `[Interface]` 写入 `MTU = 1280` |
| 服务句柄无效崩溃 | Go 服务无标准句柄 → `ERROR_INVALID_HANDLE` | svc `main.go` 启动时 `redirectStdHandles` |
| WFP「组不存在」 | 服务缺少 service SID | `ChangeServiceConfig2` 设 `SERVICE_SID_TYPE_UNRESTRICTED` |
| UDP 收包被 WSAECONNRESET 打断 | Windows UDP 收到 ICMP port-unreachable 抛错中断收包 | 给 amneziawg-go `bind_windows.go` 打补丁：`WSAECONNRESET/NETRESET/CONNREFUSED → goto retry`（go.mod replace） |
| 直接双击不提权 | 需管理员才能装服务 | `runner.exe.manifest` 设 `requireAdministrator`，链接器 `/MANIFESTUAC:NO` 避免 mt.exe LNK1327 冲突 |
