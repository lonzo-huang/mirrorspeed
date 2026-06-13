# MirrorSpeed VPN — 项目总览

> **技术栈**：自研混淆隧道内核（AmneziaWG 内核，对外以 MirrorSpeed 命名）· wstunnel · Nginx TLS 1.3 · FastAPI · Next.js 14 · Supabase · Stripe · AdMob · Vercel · Flutter  
> **VPN 服务器系统**：Ubuntu 22.04 / 24.04 LTS  
> **客户端**：Android / Windows / iOS（Flutter 原生，自动 UDP 直连 → WebSocket 中继回退）  
> **当前版本**：客户端 **v2.3.0**（UI 全新设计 + 双模式节点选择 + 邮箱密码登录）

> ⚠️ **对外命名约定**：面向用户的一切（服务名、目录、日志、二进制）统一使用 **MirrorSpeed**，
> 不出现 `awg` / `amneziawg` 字样。AWG 仅作为内部内核技术在本文档中提及。
> 中文壳额外**不出现 "VPN" 字样**（合规），产品名为「镜速加速器」。

---

## 0. 用户安装（通过 GitHub Release）

每次发布 `client/release.ps1` 会自动在 GitHub 创建 Release 并上传安装包。普通用户有两个入口：

**入口 A — 官网下载页（推荐给用户）**
- 打开 <https://www.mirrorspeed.com/download>（或中文页 `/cn`）。
- 页面通过 `/api/releases/latest` 读取 GitHub 最新 Release，列出 Android APK / Windows ZIP。
- 「国内高速下载」链接由 Supabase `app_config` 的 `cn_apk_url` / `cn_win_url` 决定。

**入口 B — 直接从 GitHub 下载**
- Releases 页：<https://github.com/lonzo-huang/mirrorspeed/releases/latest>
- Android 直链（始终指向最新 tag 的 arm64 APK）：
  ```
  https://github.com/lonzo-huang/mirrorspeed/releases/download/v<版本>/MirrorSpeed-<版本>-android.apk
  ```
- Windows：同目录的 `MirrorSpeed-<版本>-windows.zip`，解压后以管理员运行 `mirrorspeed_vpn.exe`。

**Android 安装步骤（给用户的说明）**
1. 手机浏览器打开上面的 APK 直链或下载页，下载 `.apk`。
2. 首次安装会提示「未知来源」/「外部来源」——按提示允许该浏览器安装应用。
3. 打开后点中间大按钮连接；首次会弹系统「VPN 连接请求」对话框，点**允许**。
4. 安装包为 **arm64-v8a 单架构**（约 30 MB），覆盖几乎所有现代手机；
   若极少数老旧 32 位机型装不上，需另出 `armeabi-v7a` 包（当前未发）。

> **APK「软件包解析失败」**：务必用 `--split-per-abi` 产出的**单架构** APK；
> 用 `--target-platform` 只裁剪 Flutter 库、不裁插件 jniLibs，会得到残缺包导致解析失败。
> 发布脚本已固定使用 `--split-per-abi` 取 `app-arm64-v8a-release.apk`。

> **国内镜像现状**：原 CN 镜像走 Vercel Blob，现已被 Vercel **suspended**（超额/封禁）。
> `release.ps1` 已加**自动回退**：Blob 上传失败时把 `cn_apk_url` 等注册为 GitHub 直链，
> 保证国内下载不断。长期方案是把镜像迁到自有服务器 / 对象存储（见「待办」）。

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

### 2.1 免费 / 付费双轨制（v2.1+ 改为按**时间**计费）

| 用户类型 | 强制额度 | 广告 | 连接节点 |
|----------|---------|------|---------|
| 免费用户 | 每日免费**时长**（默认 1800 秒 = 30 分钟） | 开屏 + 激励视频 | 全部节点 |
| 付费订阅 | 无限制 | 无广告 | 全部节点 |

- **按时间计费（现行）**：首次连接起**墙钟倒计时**，断开也继续走（防止断连刷量），归零即强制断开系统 VPN，次日 UTC 0 点重置。上限来自 `app_config.free_daily_seconds`，客户端拉取。
- **按流量计费（旧，仍保留下发但不作强制额度）**：`free_daily_bytes`，仅展示用。

**调整免费时长**（无需重新部署，立即生效）：
```sql
UPDATE public.app_config SET value = '1800' WHERE key = 'free_daily_seconds'; -- 30 分钟
UPDATE public.app_config SET value = '3600' WHERE key = 'free_daily_seconds'; -- 60 分钟
```

### 2.1.1 广告（AdMob，仅免费用户）

- **开屏广告**：启动 / 从后台恢复时展示（可跳过）；连播激励广告期间不插入。
- **激励视频解锁时长**：时长用完后点「看广告解锁」→ **一次点击连续连播**（预加载 3 条广告池，放完自动接下一条），累计满 **50 秒**发放 +30 分钟。会员被 `AdService` 内部 `_enabled=false` 完全屏蔽。

### 2.1.2 节点选择（v2.2，双模式）

- **智能分配（默认）**：客户端按 `延迟 70% + 负载 30%` 评分自动选最优节点（两台同区域机器天然均衡打散）。
- **手动选择**：节点列表显示**延迟（10 秒滚动平均，>300ms 截断显示）+ 三档负载色块**（空闲/适中/繁忙）。
- 负载数据来源：cron 每分钟从各 vpn-api `/stats` 写回 `vpn_servers.active_peers / load_percent`，`/api/mobile/configs` 随配置下发。

### 2.1.3 登录方式（v2.2）

三种，登录页顶部标签切换：① **邮箱验证码（OTP）**；② **邮箱 + 密码**（`signInWithPassword` / `signUpWithPassword`）；③ **Google SSO**。
官网 `/login` 也已加密码登录，与 App 一致。

> **Play 审核测试账号**：`review@mirrorspeed.com` / 密码 `review424242`（已确认邮箱 + 设为 VIP）。
> Email provider 无 Test OTP 框，故用密码登录给审核员。

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

### 3.1 VPN 服务器（从 GitHub 克隆安装 · 完整步骤）

> 全程在一台干净的 **Ubuntu 22.04/24.04 或 Debian 12** VPS 上以 **root** 执行。
> 更深入的说明（架构、运维、故障排查）见 [`vpn/README.md`](vpn/README.md)。

#### 步骤 0 · 准备域名与端口
1. **DNS**：给该 VPS 配一条 A 记录，如 `jp01.yourdomain.com` → 服务器公网 IP（注册时这个域名就是 `endpoint`）。
2. **放行端口**（云厂商安全组 + 服务器防火墙）：
   - `TCP 80`（Let's Encrypt 签证）、`TCP 443`（WSS 中继 + 站点伪装）
   - `UDP 30000–49999`（混淆 UDP 直连的**端口跳变范围**）

#### 步骤 1 · 克隆仓库
```bash
# 仓库为私有，需用 GitHub Personal Access Token（PAT，勾选 repo 读权限）
git clone https://<你的GitHub用户名>:<PAT>@github.com/lonzo-huang/mirrorspeed.git
cd mirrorspeed

# 或：已装并登录 gh CLI
gh repo clone lonzo-huang/mirrorspeed && cd mirrorspeed
```
> 只需要服务器相关目录，也可只拷 `vpn/` 与 `scripts/` 两个目录到服务器。

#### 步骤 2 · 一键安装（裸机脚本，推荐）
`vpn/install.sh` 会按序完成：系统调优 → Nginx+TLS → AmneziaWG 内核 → wstunnel → nftables → **端口跳变** → 首个 Peer → vpn-api，并在结尾打印**注册信息**。

```bash
# 交互式（逐项询问域名/邮箱/节点代号等）
sudo bash vpn/install.sh

# 或：环境变量预设，非交互
sudo DOMAIN="jp01.yourdomain.com" \
     EMAIL="admin@yourdomain.com" \
     SRV_NAME="JP01" SRV_DISPLAY="日本 01" SRV_LOCATION="Tokyo" \
     SRV_COUNTRY="JP" SRV_EMOJI="🇯🇵" SRV_SORT="2" \
     bash vpn/install.sh
```
- `VPN_API_SECRET` 不传会**自动生成**（每台服务器独立，结尾会打印，注册时写入 DB）。
- 安装结束会输出一段 **`INSERT INTO public.vpn_servers ...` SQL** 和一条 `register-server.sh` 命令——含**公钥、port_secret、AWG 混淆参数**，下一步直接用。

> **方式二：Docker Compose**（适合快速复制，少定制）：
> ```bash
> cd vpn/docker
> cp .env.example .env && nano .env   # 填 DOMAIN / EMAIL / VPN_API_SECRET
> docker compose up -d
> docker compose logs vpn | grep -A2 "server public key"   # 取公钥
> ```

#### 步骤 3 · 注册节点到 Portal（二选一）
安装脚本结尾已生成现成内容，**复制即可**：

- **方式 ①（最简单）**：把打印出来的整段 `INSERT INTO public.vpn_servers (...)` 贴到
  **Supabase → SQL Editor** 执行。
- **方式 ②**：在**开发机**（有 `portal/.env.local`）运行脚本打印的
  `bash scripts/register-server.sh --name JP01 --endpoint ... --pubkey ... --api-secret ... --port-secret ... --awg-params ...`。

> ⚠️ **必须随注册写入的字段**（缺一客户端就连不上）：
> `public_key`、`api_url`(`https://<域名>/vpn-api`)、`api_secret`(每台独立)、
> `port_secret`(`cat /etc/wireguard/.port-secret`)、**9 个 AWG 混淆参数**
> (`awg_jc/jmin/jmax/s1/s2/h1/h2/h3/h4`，须与 `/etc/wireguard/awg-params.env` 完全一致)。

#### 步骤 4 · 验证
```bash
# 服务器上：各服务在跑
systemctl status nginx awg-quick@awg0 wstunnel nftables vpn-api

# 查看当前动态端口 / 跳变状态
bash vpn/08-port-hopping-setup.sh status

# 从外部：vpn-api 健康检查（需带该服务器 api_secret）
curl -H "X-API-Secret: <该服务器 VPN_API_SECRET>" https://<域名>/vpn-api/health
```
注册成功后，打开 App 下拉刷新节点列表即应看到新节点（cron 每分钟回填其负载/状态）。

#### 关键文件位置（裸机）速查
| 内容 | 路径 / 命令 |
|------|------------|
| 端口跳变 secret | `cat /etc/wireguard/.port-secret` |
| AWG 混淆参数 | `cat /etc/wireguard/awg-params.env` |
| AWG 配置 | `/etc/amnezia/amneziawg/awg0.conf` |
| 增删客户端 Peer | `bash vpn/06-peer-manager.sh {add|remove|list|qrcode} <名字>` |

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
# 在 client/ 目录下，版本号由脚本自动写入 pubspec.yaml + version.dart
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "C:\tools\flutter\bin;C:\Program Files\GitHub CLI\;" + $env:PATH

# 仅 Android（最常用）
.\release.ps1 2.3.0 -SkipWindows

# Android + Windows
.\release.ps1 2.3.0
```

脚本自动完成：构建单架构 APK（`--split-per-abi` 取 arm64）+ AAB（Play 用）+ Windows ZIP → 打 Git Tag → 创建 GitHub Release → 上传产物 → CN 镜像（失败自动回退 GitHub 直链）→ 刷新下载页缓存。

> 发布后惯例：`gh release delete v<上一版> --cleanup-tag --yes` 只保留最新一版；
> 提交脚本自动写入的 `pubspec.yaml` + `version.dart`。
>
> **versionCode**：Play 不允许重复 versionCode。脚本用 `+N`（build number）映射 versionCode，
> 每次发布自增。若手动出 AAB 撞号，把 `pubspec.yaml` 的 `+N` 调大重打即可。

### 4.1 上架 Google Play 所需素材（已就绪）

| 素材 | 文件 / 值 |
|------|----------|
| 应用图标 512×512 | `client/assets/icon/play_store_512.png` |
| 特征图 1024×500 | `icon/feature_graphic_1.png` 或 `_2.png`（已去 AI 水印） |
| AAB | `release.ps1` 产出的 `MirrorSpeed-<版本>-android.aab` |
| 启动图标母版 / 自适应前景背景 | `client/assets/icon/app_icon{,_fg,_bg}.png`（`dart run flutter_launcher_icons` 生成全套 mipmap） |
| 账号删除页（Play 必填 URL） | <https://www.mirrorspeed.com/delete-account> |
| 隐私 / 条款 | `/privacy`、`/terms`（均 200） |
| 前台服务声明 | `FOREGROUND_SERVICE_SPECIAL_USE` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE="VPN"`（插件清单已正确声明；需提交录屏，用状态栏 VPN 钥匙图标演示后台保活） |

> 包名 `com.mirrorspeed.vpn`；upload key SHA-1 `E1:99:58:6A:16:76:51:AC:E6:88:07:72:AF:0A:09:92:70:5B:42:9D`。

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

---

## 9. 项目现状与待办（交接备忘 · 2026-06）

> 给后续开发者 / AI：本节是项目当前进度的快照，便于无缝接手。

### 9.1 已完成（近期）
- **客户端 v2.3.0**：UI 全新设计（参考设计师稿）—— 开屏旋转光环、主页大圆环连接按钮 + 三栏数据 + 快捷宫格、毛玻璃底部导航；新增**会员 / 设置 / 使用帮助**页面；**「我的」页保留旧设计**。
- **按时间免费试用** + **AdMob 广告**（开屏 + 激励视频连播满 50 秒解锁 +30 分钟）。
- **双模式节点选择**（智能评分 + 手动列表含 10 秒平均延迟/三档负载）。
- **三种登录**（OTP / 邮箱密码 / Google），官网登录同步加密码方式。
- **品牌图标**：替换 Flutter 默认图标为青绿盾牌；网站 favicon / OG / PWA 图标齐全。
- **Play 上架素材**：512 图标、1024×500 特征图、AAB、`/delete-account` 页、审核测试账号。
- **官网新增页**：`/help`（App 帮助按钮指向）、`/delete-account`。
- **release.ps1**：CN 镜像失败自动回退 GitHub 直链。

### 9.2 进行中 / 下一步
- **UI 还原剩余**：节点页（设计师版含搜索 + 按国家分组 + ping 条）、登录页配色统一。设计稿在 `D:\tmp\mirrorspeed ui`（**React/Vite 代码**，需用 Flutter 重写，非直接复用）。
- **Google Play 内购（IAP / Route B）**：用户已选做 IAP（而非外部支付，避免拒审）。
  - DB 迁移 `portal/supabase/migrations/015_iap_google.sql`（plans 加 `google_product_id`/`billing_period_days`；subscriptions 加 `platform`/`store_purchase_token` 等）—— **待在 Supabase SQL Editor 执行**。
  - 待建：`/api/iap/google/verify`（Play Developer API 验购买令牌）、`/api/iap/google/rtdn`（Pub/Sub 续费/退款 webhook）、Flutter `in_app_purchase` + VIP 页真实购买。
  - 需用户提供：Play 订阅商品（`vip_monthly/quarterly/yearly`）、Service Account JSON、Pub/Sub 主题。
  - VIP 页购买按钮当前为「敬请期待」占位（IAP 未接前不接外部支付）。

### 9.3 合规红线（务必遵守）
- 对外命名不出现 `awg/amneziawg`；**中文壳不出现 "VPN" 字样**（用「加速器」）。
- 上 Play 前：**隐藏 Android 端所有外部支付/升级跳转**（数字商品必须走 Google Play 结算，否则拒审）。VIP 页已不接外部支付。
- 暴露过的密钥（`VPN_API_SECRET` / `CRON_SECRET` / `PORT_SECRET`）建议轮换。

### 9.4 其它待办
- Vercel Blob 被 suspended → 国内镜像迁自有服务器 / OSS（nginx 静态托管，无流量配额）。
- 服务器侧：同步 `06-peer-manager.sh`；ES01/FRA01 迁 /21 子网；重编 `mirrorspeed_svc.exe` 做适配器描述本地化。
- 准备开 2 个新加坡站点（共 4 站）——智能分配已支持同区域均衡。
