# VPN 服务端部署与使用指南

> 技术栈：WireGuard + wstunnel + Nginx TLS 1.3 + FastAPI  
> 适用系统：Ubuntu 22.04 / 24.04 LTS，Debian 12  
> 支持两种安装方式：**Docker Compose（推荐）** 和 **Shell 脚本（裸机）**

---

## 安装方式对比

| | Docker Compose | Shell 脚本（裸机）|
|---|---|---|
| **前置要求** | Docker + Docker Compose v2 | Ubuntu/Debian 裸机，root 权限 |
| **安装步骤** | 4 步，约 3 分钟 | 多步骤，约 8 分钟 |
| **TLS 证书** | 自动签发 + 自动续期 | certbot systemd timer |
| **服务管理** | `docker compose up/down/logs` | `systemctl start/stop` |
| **数据持久化** | Docker volume | `/etc/wireguard/` |
| **复制到新服务器** | 复制 `.env`，一条命令 | 重新跑脚本 |
| **适用场景** | 新服务器首选 | 需要深度定制内核/防火墙 |

---

## 目录

1. [架构概览](#1-架构概览)
2. [方式一：Docker Compose 安装（推荐）](#2-方式一docker-compose-安装推荐)
3. [方式二：Shell 脚本安装（裸机）](#3-方式二shell-脚本安装裸机)
4. [客户端配置](#4-客户端配置)
5. [日常运维操作](#5-日常运维操作)
6. [故障排查](#6-故障排查)
7. [安全维护](#7-安全维护)
8. [Portal 后端配置](#8-portal-后端配置)
9. [添加更多服务器（快速流程）](#9-添加更多服务器快速流程)

---

## 1. 架构概览

```
员工设备
  │
  ├─[直连模式] UDP 39666 ──────────────────────────────┐
  │                                                     │
  └─[TLS封装模式] WSS 443 → Nginx → wstunnel:2080 ──┐  │
                                                     ↓  ↓
                                              WireGuard (10.200.0.1)
                                                     │
                                              企业内网 / 公网出口
```

**两种接入模式说明：**

| 模式 | 协议 | 端口 | 适用场景 |
|------|------|------|----------|
| 直连 | WireGuard UDP | 39666 | 普通网络，速度最优 |
| TLS 封装 | WebSocket over TLS | 443 | 酒店/机场/严格防火墙，UDP 被封锁时 |

**各层职责：**

```
Nginx (443)        — TLS 终结、静态站点伪装、路径路由
wstunnel (2080)    — WebSocket ↔ UDP 转换（TLS 封装模式专用）
WireGuard (39666)  — 内核级加密隧道，分配 10.200.0.0/21 子网
nftables           — 防火墙、NAT、per-IP 连接限制（Shell 脚本模式）
```

---

## 2. 方式一：Docker Compose 安装（推荐）

### 2.1 前置要求

- Linux VPS（Ubuntu 22.04+ / Debian 12+）
- 已安装 Docker 和 Docker Compose v2
- 域名 A 记录已指向本服务器
- 开放端口：TCP 80、443，UDP 39666

**安装 Docker（如未安装）：**
```bash
curl -fsSL https://get.docker.com | sh
```

### 2.2 部署步骤

```bash
# 1. 进入 Docker 目录
cd /opt/mirrorspeed/vpn/docker

# 2. 创建并编辑配置文件
cp .env.example .env
nano .env
```

`.env` 文件内容：
```bash
DOMAIN=vpn.example.com          # 已解析到本机的域名
EMAIL=admin@example.com          # Let's Encrypt 通知邮箱
VPN_API_SECRET=<openssl rand -hex 32>  # 与 Portal 共用的 API 密钥
WG_PORT=39666                    # WireGuard UDP 端口（可保持默认）
```

```bash
# 3. 启动所有服务（首次运行自动签发 TLS 证书、生成 WireGuard 密钥）
docker compose up -d

# 4. 获取 WireGuard 服务端公钥（注册到 Portal 时需要）
docker compose logs vpn | grep -A2 "server public key"
```

### 2.3 日常管理命令

```bash
# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f vpn
docker compose logs -f nginx

# 重启服务
docker compose restart vpn

# 停止全部
docker compose down

# 升级（重新构建镜像）
docker compose build --no-cache vpn
docker compose up -d vpn
```

### 2.4 数据持久化

| 内容 | 存储位置 |
|------|---------|
| WireGuard 密钥 + Peer 配置 | Docker volume `wg-data` |
| TLS 证书 | Docker volume `nginx-secrets` |

迁移到新服务器时，导出/导入 volume 即可：
```bash
# 导出（旧服务器）
docker run --rm -v wg-data:/data -v $(pwd):/backup alpine tar czf /backup/wg-data.tar.gz -C /data .

# 导入（新服务器）
docker run --rm -v wg-data:/data -v $(pwd):/backup alpine tar xzf /backup/wg-data.tar.gz -C /data
```

---

## 3. 方式二：Shell 脚本安装（裸机）

### 3.1 服务器要求

| 项目 | 最低要求 | 推荐 |
|------|----------|------|
| CPU | 1 核 | 2 核（支持 AES-NI） |
| 内存 | 512 MB | 1 GB |
| 系统盘 | 10 GB | 20 GB |
| 网络 | 独享 IP，无共享 NAT | CN2 GIA / 直连线路 |
| 操作系统 | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |

### 3.2 域名准备

1. 添加 **A 记录**指向服务器公网 IP，等待 DNS 生效（5~30 分钟）：
   ```bash
   dig +short vpn.example.com A   # 应返回服务器公网 IP
   ```

2. 开放端口：TCP 80、443，UDP 39666

### 3.3 上传脚本

```bash
# 本地执行
scp -r vpn/ root@<SERVER_IP>:/opt/mirrorspeed/
# 或在服务器上克隆仓库
git clone <仓库地址> /opt/mirrorspeed
```

### 3.4 执行一键安装

**在执行安装前，必须修改以下两个变量：**

```bash
cd /opt/mirrorspeed

# 打开 install.sh，修改顶部配置变量
nano install.sh
```

```bash
# 通过环境变量传入（推荐，无需修改文件）
DOMAIN="vpn.example.com" \
EMAIL="admin@example.com" \
VPN_API_SECRET="<openssl rand -hex 32>" \
bash /opt/mirrorspeed/install.sh
```

安装过程约需 **3 ~ 8 分钟**，依网速而定（主要耗时：apt 安装包、下载 wstunnel 二进制、certbot 签发证书）。

### 3.3 安装输出示例

安装成功后终端输出如下：

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  企业 VPN 服务端部署完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  域名:         vpn.example.com
  WAN 网卡:     ens3
  服务端公钥:   AbCdEfGh1234...
  WireGuard 子网: 10.200.0.0/21

  开放端口:
    TCP 443   — Nginx HTTPS（伪装站 + WS隧道入口）
    UDP 39666 — WireGuard 直连

  各层服务:
    Nginx     active
    WireGuard active
    wstunnel  active
    nftables  active

  验证结果: 9 通过 / 0 失败

  初始客户端配置:
    /etc/wireguard/peers/alice.conf
```

### 3.4 分步安装（可选）

如需排查问题，也可逐步执行各脚本：

```bash
bash 01-system-tune.sh          # 内核调优、BBR、IP转发
bash 02-nginx-setup.sh vpn.example.com admin@example.com  # Nginx + 证书
bash 03-wireguard-setup.sh      # WireGuard 服务端
bash 04-wstunnel-setup.sh       # wstunnel TLS 封装层
bash 05-nftables-setup.sh       # 防火墙规则
bash 06-peer-manager.sh add alice  # 添加首个客户端
```

---

## 4. 客户端配置

### 4.1 获取客户端配置文件

在服务器上为员工生成配置：

```bash
# 添加新员工 bob
bash /opt/mirrorspeed/06-peer-manager.sh add bob

# 查看 bob 的配置内容
bash /opt/mirrorspeed/06-peer-manager.sh config bob

# 配置文件保存路径
cat /etc/wireguard/peers/bob.conf
```

通过安全渠道（企业内网传输、加密邮件、1Password 等）将 `bob.conf` 发送给员工。

---

### 4.2 Windows 客户端

**安装 WireGuard：**

1. 下载安装包：[wireguard.com/install](https://www.wireguard.com/install/)
2. 安装并启动 WireGuard 客户端

**导入配置：**

1. 打开 WireGuard 客户端
2. 点击左下角 **"导入隧道配置文件"**
3. 选择收到的 `bob.conf` 文件
4. 点击 **"激活"** 即可连接

**启用 DNS over HTTPS（防 DNS 泄露）：**

以管理员身份运行 PowerShell：

```powershell
# 启用系统级 DoH
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
    /v EnableAutoDoh /t REG_DWORD /d 2 /f

# 重启 DNS 客户端服务
Restart-Service Dnscache
```

---

### 4.3 macOS 客户端

**安装 WireGuard：**

```bash
# 方式一：App Store 安装（推荐，自动更新）
# 搜索 "WireGuard" 安装官方客户端

# 方式二：Homebrew
brew install wireguard-tools
```

**导入配置（App Store 版）：**

1. 打开 WireGuard 应用
2. 点击左下角 **"+"** → **"从文件或归档导入"**
3. 选择 `bob.conf`
4. 点击激活

**命令行方式（wireguard-tools）：**

```bash
# 将配置文件放至指定目录
sudo cp bob.conf /etc/wireguard/wg0.conf

# 连接
sudo wg-quick up wg0

# 断开
sudo wg-quick down wg0
```

**启用 DNS over TLS：**

```bash
# 写入 systemd-resolved 配置（macOS 系统无需此步，iOS/Android 同理）
# macOS 推荐在 WireGuard 配置的 DNS 字段使用 1.1.1.1
```

---

### 4.4 Linux 客户端

```bash
# Ubuntu / Debian
sudo apt-get install -y wireguard-tools resolvconf

# 安装配置
sudo cp bob.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# 连接
sudo wg-quick up wg0

# 断开
sudo wg-quick down wg0

# 开机自启
sudo systemctl enable wg-quick@wg0
```

**启用 DNS over TLS（systemd-resolved）：**

```bash
sudo tee -a /etc/systemd/resolved.conf << 'EOF'
DNS=1.1.1.1
FallbackDNS=1.0.0.1
DNSOverTLS=yes
EOF
sudo systemctl restart systemd-resolved
```

---

### 4.5 iOS / Android 客户端

**App 安装：**

- iOS：App Store 搜索 **WireGuard**
- Android：Google Play 搜索 **WireGuard**，或从 [F-Droid](https://f-droid.org) 安装

**导入配置（二维码方式，推荐）：**

在服务器上生成二维码：

```bash
bash /opt/mirrorspeed/06-peer-manager.sh qrcode bob
```

终端会显示 ASCII 二维码，用手机 WireGuard App 扫描即可一键导入。

**导入配置（文件方式）：**

1. 将 `.conf` 文件通过安全方式传至手机
2. 在 WireGuard App 中点击 **"+"** → **"从文件或归档创建"**

---

### 4.6 TLS 封装模式（UDP 被封锁时）

若所在网络封锁了 UDP 流量（如部分酒店、机场 Wi-Fi），需使用 wstunnel 将 WireGuard 包装进 HTTPS。

**下载 wstunnel 客户端：**

前往 [github.com/erebe/wstunnel/releases](https://github.com/erebe/wstunnel/releases) 下载对应平台二进制。

**Linux / macOS：**

```bash
# 第一步：在后台启动 wstunnel 客户端（将 VPN 服务器 WSS 转为本地 UDP）
wstunnel client \
    --connection-retry-max-backoff-sec 10 \
    -L "udp://127.0.0.1:39666:127.0.0.1:39666?timeout_sec=0" \
    wss://vpn.example.com/secure-tunnel/ &

# 第二步：修改 WireGuard 配置中的 Endpoint
# 将 Endpoint = vpn.example.com:39666
# 改为 Endpoint = 127.0.0.1:39666

# 第三步：连接 WireGuard
sudo wg-quick up wg0
```

**Windows（PowerShell）：**

```powershell
# 第一步：后台启动 wstunnel
Start-Process wstunnel.exe -ArgumentList `
    "client --connection-retry-max-backoff-sec 10 -L `"udp://127.0.0.1:39666:127.0.0.1:39666?timeout_sec=0`" wss://vpn.example.com/secure-tunnel/" `
    -WindowStyle Hidden

# 第二步：在 WireGuard 客户端中将 Endpoint 改为 127.0.0.1:39666，然后激活
```

---

## 5. 日常运维操作

### 5.1 员工账号管理

```bash
cd /opt/mirrorspeed

# 添加新员工（自动分配 VPN IP，生成密钥对和预共享密钥）
bash 06-peer-manager.sh add alice

# 列出所有员工及其 VPN IP、在线状态
bash 06-peer-manager.sh list

# 查看并导出员工配置文件
bash 06-peer-manager.sh config alice

# 生成二维码（手机扫码导入）
bash 06-peer-manager.sh qrcode alice

# 员工离职——立即撤销接入（热生效，无需重启）
bash 06-peer-manager.sh remove alice
```

### 5.2 查看连接状态

```bash
# 查看所有 Peer 的握手时间、流量统计
wg show wg0

# 实时监控（每 2 秒刷新）
watch -n 2 wg show wg0

# 查看当前接入的 VPN IP
wg show wg0 allowed-ips
```

输出示例：

```
interface: wg0
  public key: AbCdEfGh1234...
  listening port: 39666

peer: XyZaBc5678...
  endpoint: 203.0.113.45:12345
  allowed ips: 10.200.0.2/32
  latest handshake: 23 seconds ago
  transfer: 1.24 MiB received, 856 KiB sent
```

### 5.3 服务状态检查

```bash
# 一键检查所有服务
for svc in nginx wg-quick@wg0 wstunnel nftables; do
    echo -n "${svc}: "
    systemctl is-active "${svc}"
done

# 查看各服务日志
journalctl -u nginx -n 50 --no-pager
journalctl -u wg-quick@wg0 -n 50 --no-pager
journalctl -u wstunnel -n 50 --no-pager
```

### 5.4 Nginx 与证书管理

```bash
# 测试 Nginx 配置语法
nginx -t

# 热重载 Nginx（不中断连接）
systemctl reload nginx

# 手动续期 TLS 证书（正常情况 certbot.timer 自动处理）
certbot renew --dry-run    # 测试续期（不实际续期）
certbot renew              # 实际续期

# 查看证书有效期
certbot certificates
```

### 5.5 防火墙规则管理

```bash
# 查看当前 nftables 规则
nft list ruleset

# 重新加载规则文件
nft -f /etc/nftables.conf

# 查看 per-IP 连接计数器
nft list set inet enterprise-fw tcp443_connlimit
```

---

## 6. 故障排查

### 6.1 客户端无法连接

**第一步：确认服务端各层正常：**

```bash
# 所有服务应为 active
systemctl is-active nginx wg-quick@wg0 wstunnel nftables

# WireGuard 监听 UDP 39666
ss -ulnp | grep 39666

# wstunnel 监听 TCP 2080（仅 127.0.0.1）
ss -tlnp | grep 2080

# Nginx 监听 TCP 443
ss -tlnp | grep 443
```

**第二步：从客户端侧测试连通性：**

```bash
# 测试 443 端口（HTTPS）
curl -v https://vpn.example.com/

# 测试 39666 UDP（需 netcat）
nc -u -v vpn.example.com 39666
```

**第三步：检查防火墙是否放行：**

```bash
# 确认 443 和 39666 在规则中
nft list chain inet enterprise-fw input
```

---

### 6.2 WireGuard 握手失败

```
# 症状：wg show 中 latest handshake 长时间不更新

# 检查客户端配置的公钥是否与服务端 Peer 匹配
wg show wg0 peers

# 检查服务端 wg0.conf 中该 Peer 的 AllowedIPs 是否正确
grep -A5 "bob" /etc/wireguard/wg0.conf

# 检查 IP 转发是否开启（必须为 1）
sysctl net.ipv4.ip_forward
```

---

### 6.3 速度慢或丢包

```bash
# 确认 BBR 已启用
sysctl net.ipv4.tcp_congestion_control
# 应输出：net.ipv4.tcp_congestion_control = bbr

# 检查 AES-NI 硬件加速
grep -w aes /proc/cpuinfo | head -1

# 查看网卡队列是否为 fq
tc qdisc show dev $(cat /etc/wireguard/.wan-interface)

# MTU 问题排查（WireGuard 推荐 MTU 1420）
# 在客户端配置 [Interface] 中添加：
# MTU = 1420
```

---

### 6.4 TLS 证书问题

```bash
# 查看证书详情与有效期
openssl s_client -connect vpn.example.com:443 -servername vpn.example.com \
    < /dev/null 2>/dev/null | openssl x509 -noout -dates

# certbot 续期失败排查
certbot renew --dry-run --debug

# 手动重新签发（域名 DNS 必须已生效）
certbot certonly --webroot -w /var/www/html/enterprise-portal \
    -d vpn.example.com --force-renewal
```

---

### 6.5 wstunnel 无法转发

```bash
# 查看 wstunnel 日志
journalctl -u wstunnel -n 100 --no-pager

# 确认 Nginx 能访问到 wstunnel
curl -v --max-time 5 http://127.0.0.1:2080/

# 重启 wstunnel
systemctl restart wstunnel
```

**⚠️ 重要：wstunnel 版本锁定在 v9.7.4**

`04-wstunnel-setup.sh` 固定安装 v9.7.4，**不可升级到 v10+**。

原因：wstunnel v9.7.4 使用 JWT 协议（路径 `/v1/events`，`Sec-WebSocket-Protocol` 头携带 JWT），
而 v10+ 完全重写了协议（HTTP2 + 不同的认证机制），与 MirrorSpeed 客户端不兼容。

验证 wstunnel 是否正常响应 v9 协议：

```bash
# 应返回 HTTP/1.1 101 Switching Protocols
curl -v --max-time 3 -N \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Protocol: v1, authorization.bearer.eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6IjAwMDAwMDAwLTAwMDAtNDAwMC04MDAwLTAwMDAwMDAwMDAwMCIsInAiOnsiVWRwIjp7InRpbWVvdXQiOm51bGx9fSwiciI6IjEyNy4wLjAuMSIsInJwIjozOTY2Nn0.placeholder" \
  "http://127.0.0.1:2080/v1/events" 2>&1 | grep "< HTTP"
```

若意外升级到了 v10+，执行以下命令降回 v9.7.4：

```bash
curl -fsSL https://github.com/erebe/wstunnel/releases/download/v9.7.4/wstunnel_9.7.4_linux_amd64.tar.gz \
  -o /tmp/ws.tar.gz && tar -xzf /tmp/ws.tar.gz -C /tmp
sudo install -m 755 /tmp/wstunnel /usr/local/bin/wstunnel
sudo systemctl restart wstunnel
wstunnel --version  # 应显示 wstunnel 9.7.4
```

---

## 7. 安全维护

### 7.1 手动轮换服务端密钥

```bash
# 轮换服务端 WireGuard 密钥（热生效，不断开其他 Peer 连接）
/usr/local/bin/wg-rotate-keys.sh
```

轮换后，新服务端公钥会输出到终端。需通过安全渠道通知所有员工更新其客户端配置中的 `[Peer] PublicKey` 字段。

**自动轮换计划：** 系统已配置 `wg-rotate-keys.timer`，每月 1 日 00:00 自动执行：

```bash
# 查看下次轮换时间
systemctl status wg-rotate-keys.timer

# 立即触发一次（测试）
systemctl start wg-rotate-keys.service
```

### 7.2 密钥备份

每次轮换后，旧密钥自动备份至：

```
/etc/wireguard/key-backup/<日期时间>/
```

定期将备份同步至离线存储或企业密码库（HashiCorp Vault / 1Password Enterprise）：

```bash
# 查看所有备份
ls -la /etc/wireguard/key-backup/

# 打包备份（可加密后上传至企业存储）
tar -czf wireguard-keys-backup-$(date +%F).tar.gz /etc/wireguard/key-backup/
```

### 7.3 员工离职处理 SOP

1. 立即撤销 VPN 接入（热生效，无需重启）：

   ```bash
   bash /opt/mirrorspeed/06-peer-manager.sh remove <用户名>
   ```

2. 确认 Peer 已从运行时移除：

   ```bash
   wg show wg0 peers | grep -c ""
   # 确认数量减少 1
   ```

3. 通知用户其 VPN 账号已停用。

### 7.4 定期安全检查清单

建议每月执行：

```bash
# 1. 检查所有服务状态
systemctl status nginx wg-quick@wg0 wstunnel nftables

# 2. 查看异常连接（非预期 IP 段）
wg show wg0

# 3. 检查 Nginx 错误日志
tail -100 /var/log/nginx/enterprise-error.log

# 4. 确认证书有效期（距到期 < 30 天时需关注）
certbot certificates

# 5. 检查系统安全更新
apt-get update && apt-get --dry-run upgrade | grep -i security

# 6. 应用安全更新
apt-get upgrade -y
```

---

## 8. vpn-api 管理接口（Shell 脚本模式）

> **Docker 模式无需此步骤** — vpn-api 已内置在 `vpn` 容器中。

vpn-api 是部署在每台 VPN 服务器上的 FastAPI 服务，供 Portal 远程管理 Peer。

> **每台服务器独立密钥（更新）**：Portal 现在从 `vpn_servers.api_secret` 读取**每台服务器
> 各自的**密钥（迁移 012），不再要求全机群共用同一个 `VPN_API_SECRET`。每台服务器
> `.env` 的 `VPN_API_SECRET` 须与该服务器在 DB 中的 `api_secret` 一致即可。
>
> ⚠️ **AmneziaWG 配置路径**：`06-peer-manager.sh` 必须指向
> `/etc/amnezia/amneziawg/awg0.conf`（不是 `/etc/wireguard/awg0.conf`）。仓库版本已正确；
> 若服务器上是旧版，请同步仓库版本（临时可用软链 `ln -sf /etc/amnezia/amneziawg/awg0.conf /etc/wireguard/awg0.conf`）。

```bash
# 在服务器上执行（该值需与 DB vpn_servers.api_secret 一致）
sudo VPN_API_SECRET=<该服务器密钥> bash /opt/mirrorspeed/07-vpnapi-setup.sh
```

验证：
```bash
curl https://<DOMAIN>/vpn-api/health
curl -H "X-API-Secret: <VPN_API_SECRET>" https://<DOMAIN>/vpn-api/stats
```

---

## 9. Portal 后端配置

Portal（Next.js）通过 Supabase 存储服务器列表，通过 Vercel Cron 同步服务器状态。
> Vercel **Hobby 套餐仅允许每日一次 cron**，`sync-servers` 已降级为每日（`portal/vercel.json`）。
> 需更高频请升级套餐或用外部定时器带 `CRON_SECRET` 调用。

### 9.1 Supabase 数据库迁移

在 [Supabase Dashboard](https://supabase.com) → SQL Editor 依次执行：

```
portal/supabase/migrations/001_schema.sql   # 基础表结构
portal/supabase/migrations/002_rls.sql      # 行级安全策略
portal/supabase/migrations/003_servers.sql  # 多服务器支持
portal/supabase/migrations/012_vpn_servers_api_secret.sql   # 每服务器独立 api_secret 列
portal/supabase/migrations/013_vpn_device_peers_unique.sql  # (device,server) 唯一索引防重复 peer
```

> 012 后需为每台服务器写入密钥：
> `UPDATE public.vpn_servers SET api_secret = '<该服务器密钥>' WHERE name = 'ES01';`
> 013 执行前需先清理历史重复活跃 peer，否则建唯一索引会失败。

### 9.2 Vercel 环境变量

| 变量名 | 说明 | 生成方式 |
|--------|------|----------|
| `VPN_API_SECRET` | 旧版全局密钥（现已改为每服务器 `vpn_servers.api_secret`，见迁移 012） | `openssl rand -hex 32` |
| `APP_ENCRYPTION_SECRET` | 加密存储在 DB 中的 WireGuard 私钥 | `openssl rand -hex 32` |
| `CRON_SECRET` | Vercel Cron Job 鉴权 | `openssl rand -hex 16` |

使用 Vercel CLI 批量设置（在本机项目根目录执行）：

```bash
echo "<VPN_API_SECRET值>"    | vercel env add VPN_API_SECRET    production
echo "<APP_SECRET值>"        | vercel env add APP_ENCRYPTION_SECRET production
echo "<CRON_SECRET值>"       | vercel env add CRON_SECRET        production

# 修改后必须重新部署
vercel deploy --prod
```

### 9.3 注册服务器到 Supabase

在 Supabase SQL Editor 执行（替换为真实值）：

```sql
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

> `api_secret`（迁移 012）必须与该服务器一致；`port_secret` 供客户端计算 HMAC 动态端口。

---

## 10. 添加更多服务器（快速流程）

准备好新 VPS 后，完整流程约 10 分钟：

### 第一步：服务器端部署（在新 VPS 上执行）

```bash
# 1. 上传脚本（在本机执行）
scp -r vpn/ root@<NEW_SERVER_IP>:/opt/mirrorspeed/
scp -r vpn-api/ root@<NEW_SERVER_IP>:/opt/mirrorspeed/vpn-api/

# 2. SSH 到新服务器，一键部署
ssh root@<NEW_SERVER_IP>

DOMAIN="jp01.yourdomain.com" \
EMAIL="admin@yourdomain.com" \
VPN_API_SECRET="<本服务器独立密钥，注册时写入 DB api_secret>" \
bash /opt/mirrorspeed/install.sh
```

安装完成后，记录脚本末尾输出的 **WireGuard 服务端公钥**。

### 第二步：注册到 Portal（在本机执行）

使用 `scripts/register-server.sh` 脚本一键完成 Supabase 注册 + Vercel 重部署：

```bash
bash scripts/register-server.sh \
  --name     JP01 \
  --display  "日本 01" \
  --location "Tokyo" \
  --country  JP \
  --emoji    "🇯🇵" \
  --endpoint jp01.yourdomain.com \
  --pubkey   "<WireGuard公钥>" \
  --sort     2
```

脚本自动完成：
- 连接健康检查（确认 vpn-api 可达）
- 插入 Supabase `vpn_servers` 表
- 触发 Vercel 重新部署
- 调用 cron 验证状态同步

### 第三步：验证

```bash
# 查看所有服务器状态
curl https://www.mirrorspeed.com/api/servers | python3 -m json.tool

# 触发状态同步（等约 1 分钟也会自动同步）
curl https://www.mirrorspeed.com/api/cron/sync-servers \
  -H "Authorization: Bearer <CRON_SECRET>"
```

---

## 附录：文件结构速查

```
项目根目录/
├── scripts/
│   └── register-server.sh      # 本机执行：注册新服务器到 Portal
├── vpn/
│   ├── install.sh              # 一键安装主控脚本（服务器上执行）
│   ├── 01-system-tune.sh       # 内核调优（BBR、IP转发、缓冲区）
│   ├── 02-nginx-setup.sh       # Nginx TLS + 证书 + 路径路由
│   ├── 03-wireguard-setup.sh   # WireGuard 服务端 + 密钥轮换
│   ├── 04-wstunnel-setup.sh    # wstunnel WebSocket 封装层
│   ├── 05-nftables-setup.sh    # 防火墙规则（持久化）
│   ├── 06-peer-manager.sh      # 客户端 Peer 管理
│   └── 07-vpnapi-setup.sh      # vpn-api FastAPI 管理接口部署
├── vpn-api/
│   └── main.py                 # FastAPI 服务（部署到每台 VPN 服务器）
└── portal/
    ├── supabase/migrations/    # 数据库迁移 SQL 文件
    └── src/                    # Next.js Portal 源码

/opt/mirrorspeed/               # 服务器上的部署目录
├── install.sh + 0x-*.sh        # 安装脚本
├── vpn-api/
│   ├── main.py                 # FastAPI 源码
│   ├── venv/                   # Python 虚拟环境
│   └── .env                    # VPN_API_SECRET（chmod 600）
└── 06-peer-manager.sh          # 随时可调用的 Peer 管理工具

/etc/wireguard/
├── wg0.conf                    # WireGuard 服务端配置（含所有 Peer）
├── server-private.key          # 服务端私钥（chmod 600，勿外传）
├── server-public.key           # 服务端公钥
├── .wan-interface              # 检测到的 WAN 网卡名
├── peers/                      # 客户端配置目录
│   ├── alice.conf              # 完整客户端配置（可直接导入）
│   ├── alice.meta              # 元数据（IP、公钥、创建时间）
│   ├── alice.private           # 私钥（仅服务端存留）
│   └── alice.psk               # 预共享密钥
└── key-backup/                 # 密钥轮换历史备份
```

---

*如遇问题请检查 `journalctl -u wg-quick@wg0`、`journalctl -u nginx`、`journalctl -u vpn-api` 日志，或联系 IT 管理员。*
