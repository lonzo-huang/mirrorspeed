# MirrorSpeed VPN — 项目总览

> **技术栈**：WireGuard · wstunnel · Nginx TLS 1.3 · FastAPI · Next.js 14 · Supabase · Stripe · Vercel · Flutter  
> **VPN 服务器系统**：Ubuntu 22.04 / 24.04 LTS  
> **客户端**：Android / Windows（Flutter 原生，自动 WireGuard → WebSocket 中继回退）

---

## 目录结构

```
MirrorSpeed/
├── client/              # Flutter 移动端（Android / Windows）
├── portal/              # Next.js 官网 + 管理后台（托管于 Vercel）
├── vpn/                 # VPN 服务器安装
│   ├── docker/          #   ├─ Docker Compose 安装（推荐）
│   │   ├── docker-compose.yml
│   │   ├── .env.example
│   │   ├── vpn/         #   │    WireGuard + wstunnel + vpn-api
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
  ├─[直连] UDP 39666 ────────────────────────────────────┐
  │                                                       │
  └─[中继] WSS 443 → Nginx /secure-tunnel/ → wstunnel ──┤
                                                         ↓
                                               WireGuard 服务器
                                               10.200.0.0/24
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
         ├─ 创建 / 删除 WireGuard Peer
         ├─ 查询 Peer 流量（wg show dump）
         └─ 暂停 / 恢复 Peer（AllowedIPs 清零）
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

### 2.2 连接协议回退

App 连接时自动选择最优方式：

1. **直连 WireGuard**（UDP 39666）— 延迟最低，优先使用
2. **WebSocket 中继**（WSS 443 → wstunnel）— 12 秒内未连接自动切换，绕过 GFW 封锁

切换后 App 主页显示橙色"WebSocket 中继"徽章。

### 2.3 Cron 自动化（每分钟）

Vercel Cron 每分钟调用 `/api/cron/sync-servers`，自动完成：
- 同步每台服务器 CPU / 内存 / 带宽 / 延迟状态
- 更新每个 Peer 的今日已用流量（`wg show dump`）
- 超额免费用户：自动暂停 Peer（断开连接）
- 次日 UTC 0 点：自动恢复 Peer

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

安装完成后记录输出的 **WireGuard 服务端公钥**，注册服务器时需要。

### 3.2 Supabase 数据库

在 [Supabase Dashboard](https://supabase.com/dashboard) → SQL Editor 依次执行：

```
portal/supabase/migrations/001_schema.sql    # 基础表结构
portal/supabase/migrations/002_rls.sql       # 行级安全策略
portal/supabase/migrations/003_servers.sql   # 多服务器支持
portal/supabase/migrations/004_free_quota.sql # 免费流量额度追踪
```

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
  endpoint, port, public_key, api_url, sort_order
) VALUES (
  'HK01', '香港 01', 'Hong Kong', 'HK', '🇭🇰',
  'hk01.yourdomain.com', 39666,
  '<WireGuard 服务端公钥>',
  'https://hk01.yourdomain.com/vpn-api',
  1
);
```

---

## 4. Flutter 客户端发布

```powershell
# 在 client/ 目录下，更新 pubspec.yaml 版本号后执行：
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:PATH = "C:\tools\flutter\bin;C:\Program Files\GitHub CLI\;" + $env:PATH

# 仅 Android
.\release.ps1 1.0.7 -SkipWindows

# Android + Windows
.\release.ps1 1.0.7
```

脚本自动完成：构建 APK / ZIP → 打 Git Tag → 创建 GitHub Release → 上传产物。

---

## 5. 关键环境变量速查

| 变量名 | 用途 | 位置 |
|--------|------|------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase 项目 URL | Vercel |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase 匿名密钥 | Vercel |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase 管理员密钥 | Vercel |
| `VPN_API_SECRET` | VPN 服务器 API 鉴权（所有服务器共用） | Vercel + 每台 VPN 服务器 `.env` |
| `APP_ENCRYPTION_SECRET` | WireGuard 私钥加密密钥 | Vercel |
| `CRON_SECRET` | Vercel Cron 鉴权 | Vercel + `client/release.ps1` |
| `GITHUB_TOKEN` | 私有仓库 Release 下载 | Vercel |
| `GITHUB_REPO` | 仓库路径（`owner/repo`） | Vercel |

---

## 6. 日常运维

### 查看服务器状态
```bash
# 服务器上执行
systemctl status nginx wg-quick@wg0 wstunnel nftables vpn-api

# 查看活跃 VPN 连接
wg show wg0
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
| App 连接不上 | 服务器 UDP 39666 是否开放；`wg show wg0` 有无该 Peer |
| 显示 0 个节点 | `vpn_device_peers` 是否有记录；`vpn-api /peers` 是否正常 |
| 流量不同步 | Vercel Cron 是否启用；`CRON_SECRET` 是否与 vercel.json 一致 |
| 下载页版本不更新 | `GITHUB_TOKEN` 是否配置；`/api/releases/latest` 是否返回 200 |
| 中继模式不生效 | `wstunnel` 服务是否运行；Nginx `/secure-tunnel/` 配置是否存在 |
| 付费用户被限速 | `subscriptions` 表 `status` 是否为 `active` |

---

## 8. 技术架构详解

### WireGuard 配置生成流程

```
用户登录 → 注册设备（vpn_devices）
  → Portal 调用每台 VPN 服务器 vpn-api POST /peers
  → 服务器生成密钥对，写入 wg0.conf
  → Portal 将加密私钥存入 vpn_device_peers
  → App 调用 GET /api/mobile/configs
  → Portal 解密私钥，生成 wg_conf 字符串
  → App 用 wireguard_flutter 建立 VPN 隧道
```

### 流量计量流程

```
Vercel Cron (每分钟)
  → 调用 vpn-api GET /peers（含 rx_bytes + tx_bytes）
  → 计算增量（处理 WireGuard 重启归零）
  → 更新 vpn_device_peers.daily_bytes
  → 超过 app_config.free_daily_bytes → PATCH /peers/{name}/status {active: false}
  → 次日 UTC 0 点 → PATCH /peers/{name}/status {active: true}，重置计数器
```
