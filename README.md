# Enterprise VPN 系统部署指南

> **技术栈**：WireGuard · Nginx TLS 1.3 · wstunnel · FastAPI · Next.js · Supabase · Stripe · Vercel  
> **适用系统**：VPN 服务器 Ubuntu 22.04/24.04 LTS；Portal 托管于 Vercel  
> **客户端**：Clash Meta（订阅链接自动同步，支持多服务器自动选速）

---

## 目录

**A — 整体架构**
1. [系统架构总览](#1-系统架构总览)
2. [部署前准备清单](#2-部署前准备清单)

**B — VPN 服务器**
3. [每台 VPN 服务器：基础安装](#3-每台-vpn-服务器基础安装)
4. [每台 VPN 服务器：部署管理 API](#4-每台-vpn-服务器部署管理-api)

**C — Portal 部署**
5. [Supabase 配置](#5-supabase-配置)
6. [Stripe 支付配置](#6-stripe-支付配置)
7. [Vercel 部署 Portal](#7-vercel-部署-portal)
8. [注册服务器到 Portal](#8-注册服务器到-portal)

**D — 客户端使用**
9. [用户注册与订阅](#9-用户注册与订阅)
10. [Clash 客户端配置](#10-clash-客户端配置)
11. [TLS 封装模式（UDP 受限网络）](#11-tls-封装模式udp-受限网络)

**E — 运维管理**
12. [日常运维操作](#12-日常运维操作)
13. [多服务器管理](#13-多服务器管理)
14. [故障排查](#14-故障排查)
15. [安全维护](#15-安全维护)

**附录**
- [文件结构速查](#附录a文件结构速查)
- [环境变量速查](#附录b环境变量速查)

---

## 1. 系统架构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                         用户侧                                    │
│   浏览器（注册/付费/管理设备）      Clash 客户端（自动多服务器）     │
└──────────┬──────────────────────────────────┬───────────────────┘
           │ HTTPS                            │ GET /api/sub/{token}
           ▼                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Portal  (Next.js on Vercel)                     │
│  页面：登录 · Dashboard · 设备 · 账单 · 服务器状态               │
│  API：/api/auth  /api/devices  /api/sub  /api/billing           │
│  Cron：每分钟轮询所有服务器 → 刷新延迟/负载缓存                  │
└──────┬──────────────────────────────┬───────────────────────────┘
       │                              │ 内部 API (X-API-Secret)
       ▼                              ▼
┌────────────┐          ┌─────────────────────────────────────────┐
│  Supabase  │          │  VPN 服务器群（可水平扩展）               │
│  Auth      │          │                                         │
│  PostgreSQL│          │  HK01  SG01  JP01  US01  ...           │
│  RLS       │          │  每台：WireGuard + Nginx + wstunnel     │
└────────────┘          │          + FastAPI 管理 API             │
       │                └─────────────────────────────────────────┘
       ▼
┌────────────┐
│   Stripe   │
│ 订阅/计费  │
└────────────┘
```

**用户完整使用流程：**
```
注册（Google/Microsoft/邮箱）
  → 选择套餐 → Stripe 支付
  → Dashboard 点击「添加设备」
  → 系统自动在所有 VPN 服务器上创建 WireGuard Peer
  → 复制订阅链接粘贴到 Clash → 所有服务器自动出现 → 自动测速选最快
```

---

## 2. 部署前准备清单

在开始前，请确认以下资源已就绪：

### VPN 服务器（每台）

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu 22.04 / 24.04 LTS |
| CPU | ≥ 1 核，**必须支持 AES-NI**（`grep -w aes /proc/cpuinfo`） |
| 内存 | ≥ 512 MB（推荐 1 GB） |
| 网络 | 独享 IP，非共享 NAT；推荐 CN2 GIA 或直连线路 |
| 域名 A 记录 | `hk01.vpn.example.com` → 该服务器 IP（**每台服务器单独子域名**） |

### Portal 服务

| 服务 | 用途 | 免费额度 |
|------|------|----------|
| [Vercel](https://vercel.com) | 托管 Next.js | 免费层够用 |
| [Supabase](https://supabase.com) | 数据库 + Auth | 免费层够用 |
| [Stripe](https://stripe.com) | 支付处理 | 按交易收费 |
| GitHub | 代码仓库（Vercel 部署源） | 免费 |

### 本地工具

```bash
node --version    # ≥ 18
npm --version     # ≥ 9
# Supabase CLI（可选，用于本地调试）
npm install -g supabase
```

---

## 3. 每台 VPN 服务器：基础安装

> **每台服务器独立执行以下步骤**，域名替换为该服务器专属子域名。

### 3.1 系统初始化

```bash
# 以 root 登录后执行
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git dnsutils python3 python3-pip

# 上传项目 vpn/ 目录到服务器
scp -r vpn/ root@<SERVER_IP>:/opt/enterprise-vpn/
# 或直接 git clone
# git clone <仓库地址> /tmp/repo && cp -r /tmp/repo/vpn /opt/enterprise-vpn
```

### 3.2 确认域名 DNS 已生效

```bash
# 在服务器上执行，应返回本机公网 IP
dig +short hk01.vpn.example.com A
```

⚠️ **DNS 未生效前不要执行安装脚本**，Let's Encrypt 签发证书需要域名可解析。

### 3.3 执行一键安装

```bash
cd /opt/enterprise-vpn
chmod +x *.sh

DOMAIN="hk01.vpn.example.com" \
EMAIL="admin@example.com" \
bash install.sh
```

安装约 **3 ~ 8 分钟**，完成后输出：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  企业 VPN 服务端部署完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  域名:      hk01.vpn.example.com
  WAN 网卡:  ens3
  服务端公钥: AbCdEfGh1234...         ← 记录此公钥，后续注册到 Portal
  验证结果: 9 通过 / 0 失败
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**记录服务端公钥**（后续第 8 步要填入 Supabase）：

```bash
cat /etc/wireguard/server-public.key
```

---

## 4. 每台 VPN 服务器：部署管理 API

Portal 通过 FastAPI 远程管理每台服务器的 WireGuard Peer，**每台服务器都需要部署**。

### 4.1 安装依赖

```bash
pip3 install fastapi "uvicorn[standard]" python-dotenv psutil
```

### 4.2 上传 vpn-api 目录

```bash
scp -r vpn-api/ root@<SERVER_IP>:/opt/enterprise-vpn/vpn-api/
```

### 4.3 配置环境变量

```bash
cd /opt/enterprise-vpn/vpn-api
cp .env.example .env
nano .env
```

填入内容（与 Portal 共享同一个 Secret）：

```bash
VPN_API_SECRET=your-long-random-secret-key-min-32-chars
```

### 4.4 部署 systemd 服务

```bash
# 修改 vpn-api.service 中的域名为本服务器的实际域名
sed -i 's/vpn.yourcompany.com/hk01.vpn.example.com/g' \
    /opt/enterprise-vpn/vpn-api/vpn-api.service

cp /opt/enterprise-vpn/vpn-api/vpn-api.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now vpn-api
```

### 4.5 验证 API 正常运行

```bash
# 在服务器本地测试（替换 YOUR_SECRET）
curl -k https://127.0.0.1:8443/health

# 预期返回：
# {"status":"ok","wg_status":"up","timestamp":"2026-05-16T..."}
```

从 Portal 服务器（或本地）测试远程访问：

```bash
curl https://hk01.vpn.example.com:8443/health
```

> **注意**：8443 端口需要在防火墙放行，但只允许来自 Vercel 出口 IP 的请求。
> 若要严格限制，可在 nftables 中指定源 IP 白名单。

### 4.6 开放 nftables 8443 端口

```bash
# 追加规则（允许管理 API 端口）
nft add rule inet enterprise-fw input tcp dport 8443 ct state new accept

# 保存到配置文件使重启生效
nft list ruleset > /etc/nftables.conf
```

---

## 5. Supabase 配置

### 5.1 创建项目

1. 登录 [supabase.com](https://supabase.com) → **New Project**
2. 填写项目名称（如 `enterprise-vpn`），选择区域（推荐 Singapore 或 Tokyo）
3. 记录数据库密码（后续不再显示）

### 5.2 执行数据库 Migration

进入 **SQL Editor**，依次粘贴并执行以下三个文件的内容：

```
portal/supabase/migrations/001_schema.sql   ← 核心表结构
portal/supabase/migrations/002_rls.sql      ← 行级安全策略
portal/supabase/migrations/003_servers.sql  ← 多服务器支持
```

执行后确认以下表已创建：

```sql
-- 在 SQL Editor 执行验证
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- 应看到：audit_log, plans, profiles, subscriptions,
--         vpn_device_peers, vpn_devices, vpn_servers
```

### 5.3 配置 Auth

进入 **Authentication → Providers**：

**Google：**
1. 开启 Google Provider
2. 前往 [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials
3. 创建 OAuth 2.0 Client ID（Web 应用）
4. 授权重定向 URI 填：`https://your-project.supabase.co/auth/v1/callback`
5. 将 Client ID 和 Secret 填回 Supabase

**Microsoft（Azure AD）：**
1. 开启 Azure Provider
2. 前往 [Azure Portal](https://portal.azure.com) → App registrations → New registration
3. 重定向 URI 填：`https://your-project.supabase.co/auth/v1/callback`
4. 创建 Client Secret，将 Application ID 和 Secret 填回 Supabase

**邮箱 Magic Link：**
- 默认已开启，无需额外配置

### 5.4 配置重定向 URL

进入 **Authentication → URL Configuration**：

```
Site URL:
  https://portal.yourcompany.com

Redirect URLs（每行一个）:
  https://portal.yourcompany.com/api/auth/callback
  http://localhost:3000/api/auth/callback    ← 本地开发用
```

### 5.5 获取项目凭据

进入 **Settings → API**，记录：

```
Project URL:     https://xxxxxxxxxxxx.supabase.co
anon key:        eyJhbGc...（公开密钥，用于客户端）
service_role key: eyJhbGc...（私密密钥，仅服务端使用，切勿暴露）
```

---

## 6. Stripe 支付配置

### 6.1 创建产品与价格

1. 登录 [Stripe Dashboard](https://dashboard.stripe.com)
2. **Products → Add product**
   - Name: `Enterprise VPN Monthly`
   - Description: `高速企业专线，支持 2 台设备`
3. 在该产品下添加 **3 个 Price**（三种货币）：

| 货币 | 金额 | 计费周期 |
|------|------|----------|
| USD | $9.99 | Monthly |
| EUR | €9.99 | Monthly |
| CNY | ¥68.00 | Monthly |

4. 记录每个 Price 的 ID（格式 `price_xxxxxxxx`）：

```
STRIPE_PRICE_USD=price_xxxxxxxxxxxxxxxxx
STRIPE_PRICE_EUR=price_xxxxxxxxxxxxxxxxx
STRIPE_PRICE_CNY=price_xxxxxxxxxxxxxxxxx
```

5. 同样在 `plans` 表中更新这三个 Price ID：

```sql
UPDATE public.plans
SET
  stripe_price_usd = 'price_xxx',
  stripe_price_eur = 'price_xxx',
  stripe_price_cny = 'price_xxx'
WHERE name = 'Monthly VPN';
```

### 6.2 配置 Customer Portal

1. Stripe Dashboard → **Settings → Billing → Customer portal**
2. 开启 **Allow customers to cancel subscriptions**
3. 开启 **Allow customers to update payment methods**
4. 保存

### 6.3 配置 Webhook

**生产环境：**

1. Stripe Dashboard → **Developers → Webhooks → Add endpoint**
2. Endpoint URL：`https://portal.yourcompany.com/api/webhooks/stripe`
3. 监听以下事件：

```
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
invoice.payment_succeeded
invoice.payment_failed
```

4. 记录 Webhook Signing Secret（`whsec_xxxxxxxxx`）

**本地开发测试：**

```bash
# 安装 Stripe CLI
stripe listen --forward-to localhost:3000/api/webhooks/stripe

# 输出中会显示 webhook secret，填入 .env.local
# Ready! Your webhook signing secret is whsec_...
```

---

## 7. Vercel 部署 Portal

### 7.1 推送代码到 GitHub

```bash
cd portal
git init
git add .
git commit -m "init enterprise vpn portal"
# 在 GitHub 创建仓库后：
git remote add origin https://github.com/yourorg/vpn-portal.git
git push -u origin main
```

### 7.2 导入到 Vercel

1. 登录 [vercel.com](https://vercel.com) → **Add New Project**
2. 选择刚推送的 GitHub 仓库
3. Framework Preset 选择 **Next.js**
4. 点击 **Deploy**（先不填环境变量，部署会失败但没关系）

### 7.3 配置环境变量

进入 Vercel 项目 → **Settings → Environment Variables**，添加以下所有变量：

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL          = https://xxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY     = eyJhbGc...
SUPABASE_SERVICE_ROLE_KEY         = eyJhbGc...

# Stripe
STRIPE_SECRET_KEY                 = sk_live_...
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY= pk_live_...
STRIPE_WEBHOOK_SECRET             = whsec_...
STRIPE_PRICE_USD                  = price_...
STRIPE_PRICE_EUR                  = price_...
STRIPE_PRICE_CNY                  = price_...

# VPN 服务器通信（所有服务器共用一个 Secret）
VPN_API_SECRET                    = your-long-random-secret-key
VPN_SERVER_ENDPOINT               = （留空，多服务器不再使用单一端点）
VPN_SERVER_PORT                   = 51820

# 应用配置
NEXT_PUBLIC_APP_URL               = https://portal.yourcompany.com
APP_ENCRYPTION_SECRET             = （32位随机字符串，用于加密私钥）

# Cron 鉴权
CRON_SECRET                       = （随机字符串，防止外部触发 cron）
```

> **生成随机 Secret：**
> ```bash
> # Linux/macOS
> openssl rand -hex 32
> # 或
> node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
> ```

### 7.4 重新部署

```bash
# 触发重新部署
vercel --prod
# 或在 Vercel Dashboard 点击 Redeploy
```

### 7.5 绑定自定义域名（可选）

1. Vercel → Settings → Domains → Add `portal.yourcompany.com`
2. 在 DNS 服务商添加 CNAME 记录：
   ```
   portal.yourcompany.com  →  cname.vercel-dns.com
   ```

### 7.6 验证 Portal 正常运行

```bash
# 访问登录页
curl -I https://portal.yourcompany.com/login

# 测试 Cron 接口（替换 CRON_SECRET）
curl -H "Authorization: Bearer YOUR_CRON_SECRET" \
     https://portal.yourcompany.com/api/cron/sync-servers
```

---

## 8. 注册服务器到 Portal

每部署一台新 VPN 服务器后，需要在 Supabase 中注册其信息，Portal 才能管理该服务器并在界面上展示其状态。

### 8.1 获取服务器公钥

在每台 VPN 服务器上：

```bash
cat /etc/wireguard/server-public.key
```

### 8.2 在 Supabase 中注册

进入 Supabase → **Table Editor → vpn_servers**，点击 Insert row，逐台填入：

| 字段 | HK01 示例 | 说明 |
|------|-----------|------|
| `name` | `HK01` | 服务器代号（用于 peer 命名） |
| `display_name` | `香港 01` | 界面显示名称 |
| `location` | `Hong Kong` | 城市名 |
| `country_code` | `HK` | ISO 两字母国家码 |
| `flag_emoji` | `🇭🇰` | 国旗 emoji |
| `endpoint` | `hk01.vpn.example.com` | 服务器域名 |
| `port` | `51820` | WireGuard 端口 |
| `public_key` | `AbCd...（公钥内容）` | 第 3 步记录的 WireGuard 公钥 |
| `api_url` | `https://hk01.vpn.example.com:8443` | FastAPI 地址 |
| `max_peers` | `200` | 该服务器最大用户数上限 |
| `sort_order` | `1` | 排序（越小越靠前） |
| `is_active` | `true` | 是否启用 |

**或使用 SQL 批量插入：**

```sql
-- 删除示例占位数据
DELETE FROM public.vpn_servers WHERE public_key LIKE 'PLACEHOLDER%';

-- 插入真实服务器
INSERT INTO public.vpn_servers
  (name, display_name, location, country_code, flag_emoji, endpoint, port, public_key, api_url, max_peers, sort_order)
VALUES
  ('HK01', '香港 01', 'Hong Kong',  'HK', '🇭🇰', 'hk01.vpn.example.com', 51820, '实际公钥HK01', 'https://hk01.vpn.example.com:8443', 200, 1),
  ('SG01', '新加坡 01','Singapore', 'SG', '🇸🇬', 'sg01.vpn.example.com', 51820, '实际公钥SG01', 'https://sg01.vpn.example.com:8443', 200, 2),
  ('JP01', '日本 01',  'Tokyo',     'JP', '🇯🇵', 'jp01.vpn.example.com', 51820, '实际公钥JP01', 'https://jp01.vpn.example.com:8443', 200, 3);
```

### 8.3 验证状态同步

等待约 1 分钟（Vercel Cron 触发），在 Portal Dashboard 应看到服务器卡片出现延迟和负载数据：

```bash
# 手动触发一次同步（立即看到结果）
curl -H "Authorization: Bearer YOUR_CRON_SECRET" \
     https://portal.yourcompany.com/api/cron/sync-servers

# 预期返回：
# {"synced":3,"failed":0,"results":[...],"timestamp":"..."}
```

---

## 9. 用户注册与订阅

### 9.1 用户注册流程

1. 访问 `https://portal.yourcompany.com/login`
2. 选择登录方式：
   - **Google 账号** → 授权后自动注册
   - **Microsoft 账号** → 授权后自动注册
   - **邮箱** → 收到 Magic Link 邮件，点击链接登录
3. 首次登录自动创建账户，跳转到 Dashboard

### 9.2 购买订阅

1. Dashboard → **订阅与账单**
2. 选择结算货币（USD / EUR / CNY）
3. 点击 **立即订阅** → 跳转 Stripe Checkout
4. 填写信用卡信息完成支付
5. 支付成功 → 自动返回 Dashboard，订阅状态变为「有效」

### 9.3 添加设备

1. Dashboard → **我的设备** → **添加新设备**
2. 填写设备名称（如「公司 MacBook」），选择系统类型
3. 点击 **添加**

系统会在**所有 VPN 服务器**上同时创建 WireGuard Peer（约 5 ~ 15 秒），完成后设备卡片显示：
- 各服务器的独立密钥已生成
- 订阅链接（用于 Clash）已就绪

---

## 10. Clash 客户端配置

> Clash Meta（Mihomo）原生支持 WireGuard 代理类型，订阅链接包含所有服务器配置，自动测速选最快。

### 10.1 安装 Clash Meta

| 平台 | 推荐客户端 | 下载地址 |
|------|-----------|----------|
| Windows | Clash Verge Rev | [github.com/clash-verge-rev](https://github.com/clash-verge-rev/clash-verge-rev/releases) |
| macOS | Clash Verge Rev | 同上 |
| iOS | Stash / Shadowrocket | App Store |
| Android | Clash Meta for Android | [github.com/MetaCubeX](https://github.com/MetaCubeX/ClashMetaForAndroid/releases) |
| Linux | Clash Meta CLI | [github.com/MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo/releases) |

> ⚠️ 必须使用 **Clash Meta（Mihomo）内核**，原版 Clash 不支持 WireGuard。

### 10.2 获取订阅链接

1. Portal → **我的设备** → 找到对应设备
2. 复制「Clash 订阅链接」：
   ```
   https://portal.yourcompany.com/api/sub/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

### 10.3 添加订阅（以 Clash Verge Rev 为例）

**Windows / macOS（Clash Verge Rev）：**

1. 打开 Clash Verge Rev → 左侧 **订阅**
2. 点击右上角 **+** → 粘贴订阅链接
3. 点击 **导入**，等待拉取成功
4. 勾选该订阅 → 点击 **使用**

**Android（Clash Meta for Android）：**

1. 主界面 → **配置** → **+**
2. 选择 **URL** → 粘贴订阅链接 → **确认**

**iOS（Stash）：**

1. 首页 → 配置 → 从 URL 下载 → 粘贴链接

### 10.4 验证连接

订阅导入后，Clash 会自动：
1. 拉取包含所有服务器的 WireGuard 配置
2. 对每个服务器进行延迟测试
3. 在「🚀 自动选择」组中选择延迟最低的服务器

**在 Clash 面板中应看到：**

```
代理组
├── 🚀 自动选择 ← 默认走此组，自动选最快
│   ├── 🇭🇰 香港 01  [32ms]
│   ├── 🇸🇬 新加坡 01  [58ms]
│   └── 🇯🇵 日本 01  [45ms]
└── 🔒 企业VPN（手动选择）
    ├── 🚀 自动选择
    ├── 🇭🇰 香港 01
    ├── 🇸🇬 新加坡 01
    └── 🇯🇵 日本 01
```

**测试连通性：**

```bash
# 在启用 Clash 后，访问以下地址确认流量走了 VPN
curl https://ipinfo.io/json
# 应显示 VPN 服务器所在地区的 IP

# 测试延迟
ping 10.200.0.1   # VPN 网关
```

### 10.5 订阅自动更新

配置文件中已设置 `Profile-Update-Interval: 24`，Clash 每 24 小时自动拉取最新配置。

如需手动刷新（如服务器增减后立即生效）：
- Clash Verge Rev：订阅页 → 右键 → **更新**

---

## 11. TLS 封装模式（UDP 受限网络）

部分网络环境（酒店、机场、某些企业防火墙）封锁 UDP，此时 WireGuard 直连无法使用，需通过 TLS/WebSocket 封装绕过限制。

### 11.1 下载 wstunnel 客户端

前往 [github.com/erebe/wstunnel/releases](https://github.com/erebe/wstunnel/releases) 下载对应平台版本。

### 11.2 启动 wstunnel 并修改配置

**Linux / macOS：**

```bash
# 将目标服务器（如香港）的 WSS 转为本地 UDP
wstunnel client \
    --connection-retry-max-backoff-sec 10 \
    -L "udp://127.0.0.1:51820:127.0.0.1:51820?timeout_sec=0" \
    wss://hk01.vpn.example.com/secure-tunnel/ &

# 在 Clash 代理配置中，将该服务器的 server 改为 127.0.0.1
# 或下载配置文件手动修改后导入
```

**Windows（PowerShell）：**

```powershell
Start-Process .\wstunnel.exe -ArgumentList `
    "client --connection-retry-max-backoff-sec 10 -L `"udp://127.0.0.1:51820:127.0.0.1:51820?timeout_sec=0`" wss://hk01.vpn.example.com/secure-tunnel/" `
    -WindowStyle Hidden
```

> 💡 Clash 配置中的服务器延迟数据在 TLS 封装模式下不准确，实际延迟会有所增加（约增加 10 ~ 30ms）。

---

## 12. 日常运维操作

### 12.1 查看实时服务器状态

**Portal 界面**：Dashboard → 服务器状态卡片（每 30 秒自动刷新）

**服务器端命令行**：

```bash
# 查看 WireGuard 所有 Peer 状态（握手时间、流量）
wg show wg0

# 实时监控
watch -n 2 wg show wg0

# 查看服务器 API 实时数据
curl -s -H "X-API-Secret: YOUR_SECRET" \
     https://hk01.vpn.example.com:8443/stats | python3 -m json.tool
```

### 12.2 服务健康检查

```bash
# 在各 VPN 服务器上执行（所有服务应为 active）
for svc in nginx wg-quick@wg0 wstunnel nftables vpn-api; do
    echo -n "  ${svc}: "
    systemctl is-active "${svc}"
done
```

### 12.3 用户管理（通过 Portal）

用户的全生命周期由 Portal 自动管理：

| 操作 | 触发方式 | 自动执行 |
|------|----------|----------|
| 用户注册 | 用户登录 | 创建 Profile |
| 开通 VPN | 支付成功（Stripe Webhook） | 在所有服务器创建 Peer |
| 添加设备 | 用户点击 Dashboard | 在所有服务器创建新 Peer |
| 删除设备 | 用户点击 Dashboard | 从所有服务器删除 Peer |
| 订阅到期 | Stripe 扣款失败 | 停用所有 Peer |
| 续费 | Stripe 自动扣款 | 恢复 active 状态 |

**Admin 手动操作**（Supabase Table Editor）：

```sql
-- 查看所有用户订阅状态
SELECT p.email, s.status, s.expires_at, s.currency
FROM profiles p
LEFT JOIN subscriptions s ON s.user_id = p.id
ORDER BY s.created_at DESC;

-- 查看所有活跃设备数
SELECT p.email, COUNT(d.id) as devices
FROM profiles p
JOIN vpn_devices d ON d.user_id = p.id AND d.is_active = true
GROUP BY p.email;

-- 手动授予管理员权限
UPDATE profiles SET role = 'admin' WHERE email = 'admin@example.com';

-- 手动停用某用户的所有设备（紧急处理）
UPDATE vpn_devices SET is_active = false
WHERE user_id = (SELECT id FROM profiles WHERE email = 'user@example.com');
```

### 12.4 证书管理

```bash
# 查看证书有效期（所有 VPN 服务器执行）
certbot certificates

# 手动续期（certbot.timer 每天自动检查，距到期 < 30 天自动续期）
certbot renew --dry-run   # 演习
certbot renew             # 实际续期

# 续期后重载 Nginx 和 vpn-api
systemctl reload nginx
systemctl restart vpn-api
```

---

## 13. 多服务器管理

### 13.1 新增服务器

1. 购买新服务器，执行 **第 3 步和第 4 步**（基础安装 + API 部署）
2. 执行第 8 步将新服务器注册到 Supabase
3. 等待下次 Cron 触发（约 1 分钟），Portal 自动识别新服务器
4. **已有用户的设备不会自动获得新服务器**（仅新添加的设备会包含）

如需为已有设备补充新服务器的 Peer，执行：

```sql
-- 查询缺少新服务器 Peer 的设备
SELECT d.id, d.device_label, p.email
FROM vpn_devices d
JOIN profiles p ON p.id = d.user_id
WHERE d.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM vpn_device_peers dp
    WHERE dp.device_id = d.id
      AND dp.server_id = 'NEW_SERVER_UUID'
  );
```

然后通过 Portal Admin 界面（或手动调用 API）为这些设备补充 Peer。

### 13.2 下线服务器

```sql
-- 在 Supabase 中将服务器标记为 inactive
UPDATE vpn_servers SET is_active = false WHERE name = 'HK01';
```

效果：
- 新用户添加设备时不再在此服务器上创建 Peer
- 已有 Peer 不会自动删除（用户现有配置继续可用直到订阅到期）
- 服务器状态不再被 Cron 轮询
- Clash 订阅拉取时会过滤掉 `status = 'offline'` 的服务器

### 13.3 服务器状态监控说明

| 状态 | 含义 | Portal 显示 |
|------|------|-------------|
| `online` | API 响应正常，CPU < 90% | 绿色「畅通/正常」 |
| `degraded` | API 响应慢（> 500ms）或 CPU > 90% | 黄色「繁忙」|
| `offline` | API 无响应或超时 | 红色「离线」|
| `unknown` | 从未成功同步过 | 灰色 |

**延迟说明**：Portal 显示的延迟是 Vercel → VPN 服务器的网络延迟，反映服务器健康状态。用户实际客户端延迟由 Clash 的 `url-test` 组自动测量，通常更准确。

---

## 14. 故障排查

### 14.1 Clash 无法拉取订阅

```bash
# 直接 curl 订阅链接查看响应
curl -v "https://portal.yourcompany.com/api/sub/YOUR_TOKEN"

# 常见返回码：
# 200 → 正常，YAML 内容已返回
# 403 → 订阅已过期，用户需续费
# 404 → Token 无效（设备已被删除）
# 503 → 所有服务器离线
```

### 14.2 服务器状态卡片显示「离线」

```bash
# 1. 确认 VPN 服务器 vpn-api 正在运行
systemctl status vpn-api
journalctl -u vpn-api -n 50 --no-pager

# 2. 确认 8443 端口可从外部访问
curl https://hk01.vpn.example.com:8443/health

# 3. 确认 nftables 放行了 8443
nft list chain inet enterprise-fw input | grep 8443

# 4. 手动触发状态同步查看错误
curl -H "Authorization: Bearer YOUR_CRON_SECRET" \
     "https://portal.yourcompany.com/api/cron/sync-servers"
```

### 14.3 用户支付后未开通服务

```bash
# 1. 检查 Stripe Webhook 是否有失败事件
# 进入 Stripe Dashboard → Developers → Webhooks → 查看日志

# 2. 查看 Vercel 函数日志
# Vercel Dashboard → Functions → /api/webhooks/stripe → 查看日志

# 3. 查看 Supabase audit_log
# SELECT * FROM audit_log ORDER BY created_at DESC LIMIT 20;
```

### 14.4 添加设备时部分服务器失败

```bash
# 查看 Vercel 日志中的错误
# 常见原因：
# - VPN 服务器 vpn-api 未启动
# - VPN_API_SECRET 不匹配
# - 网络超时（Vercel 到 VPN 服务器延迟过高）

# 查看该设备在哪些服务器上有 Peer
SELECT dp.peer_name, s.name, dp.is_active
FROM vpn_device_peers dp
JOIN vpn_servers s ON s.id = dp.server_id
WHERE dp.device_id = 'DEVICE_UUID';
```

### 14.5 WireGuard 握手失败（客户端无法通信）

```bash
# 在 VPN 服务器上
# 确认该 Peer 存在
wg show wg0 peers

# 确认 Peer 的 AllowedIPs 设置正确
wg show wg0 dump | grep "PEER_PUBLIC_KEY"

# 确认 IP 转发开启
sysctl net.ipv4.ip_forward   # 必须为 1

# 确认 NAT 规则存在
iptables -t nat -L POSTROUTING -n
```

### 14.6 速度慢

```bash
# 确认 BBR 启用
sysctl net.ipv4.tcp_congestion_control   # 应为 bbr

# 确认 AES-NI 加速
grep -w aes /proc/cpuinfo | head -1

# 查看服务器实时带宽
# Portal Dashboard 的服务器卡片会显示当前带宽

# 如果某台服务器长期繁忙，考虑：
# 1. 调低 max_peers（减少新用户分配到此服务器）
# 2. 新增同地区服务器扩容
```

---

## 15. 安全维护

### 15.1 WireGuard 服务端密钥轮换

**手动轮换（每台服务器独立执行）：**

```bash
# 轮换密钥（热生效，不断开现有连接）
/usr/local/bin/wg-rotate-keys.sh
```

轮换后必须：
1. 获取新公钥：`cat /etc/wireguard/server-public.key`
2. 更新 Supabase `vpn_servers` 表中该服务器的 `public_key` 字段
3. 等待 Clash 客户端下次更新订阅（或手动强制更新）

**自动轮换（已配置 systemd timer，每月 1 日 00:00）：**

```bash
systemctl status wg-rotate-keys.timer   # 查看状态
systemctl start wg-rotate-keys.service  # 手动触发一次
```

> ⚠️ 自动轮换后需手动更新 Supabase 中的公钥，否则用户无法握手。建议暂不启用自动轮换，改为手动定期轮换。

### 15.2 Portal 密钥轮换

**加密密钥（APP_ENCRYPTION_SECRET）**：

此密钥用于加密存储在数据库中的 WireGuard 私钥，**轮换会导致所有已加密私钥无法解密**，需要：
1. 先解密并重新加密所有私钥（复杂）
2. 或重建所有设备的 Peer（破坏性）

建议：**不轮换**，在部署前生成一次并长期使用。

### 15.3 离职员工处理 SOP

1. Portal Admin → 找到该用户 → （未来 Admin 界面实现）
2. 临时处理（Supabase SQL）：

```sql
-- 取消订阅（将触发 Webhook 停用所有 Peer）
UPDATE subscriptions SET status = 'cancelled'
WHERE user_id = (SELECT id FROM profiles WHERE email = 'ex-employee@example.com');

-- 手动停用所有设备
UPDATE vpn_devices SET is_active = false
WHERE user_id = (SELECT id FROM profiles WHERE email = 'ex-employee@example.com');

-- 注意：VPN 服务器上的 Peer 还需要手动删除（或等订阅到期自动处理）
```

3. 在各 VPN 服务器上验证 Peer 已被清除：

```bash
# 查询该用户的 peer_name（从 vpn_device_peers 表获取）
wg show wg0 peers | grep "PEER_PUBLIC_KEY"
```

### 15.4 月度安全检查清单

每月执行以下检查：

```bash
# === 各 VPN 服务器执行 ===

# 1. 检查所有服务状态
systemctl status nginx wg-quick@wg0 wstunnel nftables vpn-api

# 2. 检查 TLS 证书有效期（< 30 天需关注）
certbot certificates | grep -A2 "Domains:"

# 3. 查看异常连接
wg show wg0 | grep "latest handshake"

# 4. 应用系统安全更新
apt-get update && apt-get --dry-run upgrade | grep -i security
apt-get upgrade -y

# 5. 检查 Nginx 错误日志
tail -100 /var/log/nginx/enterprise-error.log | grep -i error
```

```sql
-- === Supabase SQL 执行 ===

-- 6. 查看最近 30 天支付记录
SELECT COUNT(*), SUM(amount_cents)/100.0 AS revenue, currency
FROM payments
WHERE created_at > now() - interval '30 days'
  AND status = 'succeeded'
GROUP BY currency;

-- 7. 查看活跃订阅数
SELECT COUNT(*) FROM subscriptions WHERE status = 'active';

-- 8. 查看近期 audit_log 异常操作
SELECT * FROM audit_log
WHERE created_at > now() - interval '7 days'
ORDER BY created_at DESC LIMIT 50;
```

---

## 附录A：文件结构速查

```
MirrorSpeed/
├── README.md                         ← 本文档（主部署指南）
│
├── vpn/                              ← VPN 服务器脚本（每台服务器部署）
│   ├── install.sh                    # 一键安装编排脚本
│   ├── 01-system-tune.sh             # 内核调优（BBR/IP转发/缓冲区）
│   ├── 02-nginx-setup.sh             # Nginx TLS 1.3 + Let's Encrypt
│   ├── 03-wireguard-setup.sh         # WireGuard 服务端 + 密钥轮换
│   ├── 04-wstunnel-setup.sh          # WebSocket TLS 封装层
│   ├── 05-nftables-setup.sh          # 防火墙（持久化规则）
│   └── 06-peer-manager.sh            # Peer 管理（add/remove/list/qrcode）
│
├── vpn-api/                          ← VPN 管理 API（每台服务器部署）
│   ├── main.py                       # FastAPI：/stats /health /peers
│   ├── vpn-api.service               # systemd 服务定义
│   └── .env.example                  # 环境变量模板
│
└── portal/                           ← Web Portal（Vercel 托管）
    ├── vercel.json                    # Cron Job 配置（每分钟同步服务器状态）
    ├── .env.example                   # 环境变量模板
    ├── supabase/migrations/
    │   ├── 001_schema.sql            # 核心表结构 + 触发器
    │   ├── 002_rls.sql               # Row Level Security 策略
    │   └── 003_servers.sql           # 多服务器表 + vpn_device_peers
    └── src/
        ├── middleware.ts              # 路由鉴权
        ├── lib/
        │   ├── supabase/{client,server}.ts
        │   ├── stripe.ts             # Stripe 客户端
        │   ├── vpn-api.ts            # VPN 服务器 API 客户端
        │   └── clash.ts              # Clash YAML 生成 + 密钥加解密
        ├── components/
        │   ├── dashboard/
        │   │   ├── nav.tsx            # 顶部导航
        │   │   └── server-status.tsx  # 服务器状态卡片（实时轮询）
        │   └── billing/
        │       ├── checkout-button.tsx
        │       └── manage-button.tsx
        └── app/
            ├── (auth)/login/          # 登录页（Google/Microsoft/Email）
            ├── (dashboard)/
            │   ├── page.tsx           # 概览（订阅状态/设备/服务器状态）
            │   ├── devices/           # 设备管理
            │   └── billing/           # 订阅与账单
            └── api/
                ├── auth/callback/     # OAuth 回调
                ├── servers/           # GET 服务器列表（含缓存状态）
                ├── cron/sync-servers/ # Vercel Cron：轮询刷新服务器状态
                ├── devices/           # POST/DELETE 设备（多服务器 Peer）
                ├── sub/[token]/       # Clash 订阅（含所有服务器配置）
                ├── billing/checkout/  # 创建 Stripe Checkout Session
                ├── billing/portal/    # 跳转 Stripe Customer Portal
                └── webhooks/stripe/   # 订阅生命周期 Webhook 处理
```

---

## 附录B：环境变量速查

### VPN 服务器（`vpn-api/.env`）

| 变量 | 说明 |
|------|------|
| `VPN_API_SECRET` | 与 Portal 共享的 API 鉴权密钥（≥ 32 位随机字符串） |
| `WG_INTERFACE` | WireGuard 接口名，默认 `wg0` |

### Portal（Vercel 环境变量）

| 变量 | 必填 | 说明 |
|------|------|------|
| `NEXT_PUBLIC_SUPABASE_URL` | ✓ | Supabase 项目 URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | ✓ | Supabase 公开密钥 |
| `SUPABASE_SERVICE_ROLE_KEY` | ✓ | Supabase 服务端密钥（仅服务端） |
| `STRIPE_SECRET_KEY` | ✓ | Stripe 私钥（`sk_live_...`） |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | ✓ | Stripe 公钥（`pk_live_...`） |
| `STRIPE_WEBHOOK_SECRET` | ✓ | Stripe Webhook 签名密钥 |
| `STRIPE_PRICE_USD` | ✓ | USD 套餐 Price ID |
| `STRIPE_PRICE_EUR` | ✓ | EUR 套餐 Price ID |
| `STRIPE_PRICE_CNY` | ✓ | CNY 套餐 Price ID |
| `VPN_API_SECRET` | ✓ | 与 VPN 服务器共享的密钥（同上） |
| `NEXT_PUBLIC_APP_URL` | ✓ | Portal 域名，如 `https://portal.example.com` |
| `APP_ENCRYPTION_SECRET` | ✓ | 32 位随机字符串，加密存储私钥 |
| `CRON_SECRET` | ✓ | Vercel Cron 请求鉴权密钥 |

---

*遇到问题请先查阅 [故障排查](#14-故障排查) 章节，或检查 Vercel 函数日志和 `journalctl` 服务日志。*
