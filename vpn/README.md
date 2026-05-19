# 企业 VPN 服务端部署与使用指南

> 技术栈：WireGuard + wstunnel + Nginx TLS 1.3 + nftables  
> 适用系统：Ubuntu 22.04 / 24.04 LTS，Debian 12  
> 适用场景：企业员工安全远程办公接入

---

## 目录

1. [架构概览](#1-架构概览)
2. [部署前准备](#2-部署前准备)
3. [服务端安装](#3-服务端安装)
4. [客户端配置](#4-客户端配置)
5. [日常运维操作](#5-日常运维操作)
6. [故障排查](#6-故障排查)
7. [安全维护](#7-安全维护)

---

## 1. 架构概览

```
员工设备
  │
  ├─[直连模式] UDP 51820 ──────────────────────────────┐
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
| 直连 | WireGuard UDP | 51820 | 普通网络，速度最优 |
| TLS 封装 | WebSocket over TLS | 443 | 酒店/机场/严格防火墙，UDP 被封锁时 |

**各层职责：**

```
Nginx (443)        — TLS 终结、静态站点伪装、路径路由
wstunnel (2080)    — WebSocket ↔ UDP 转换（TLS 封装模式专用）
WireGuard (51820)  — 内核级加密隧道，分配 10.200.0.0/24 子网
nftables           — 防火墙、NAT、per-IP 连接限制
```

---

## 2. 部署前准备

### 2.1 服务器要求

| 项目 | 最低要求 | 推荐 |
|------|----------|------|
| CPU | 1 核 | 2 核（支持 AES-NI） |
| 内存 | 512 MB | 1 GB |
| 系统盘 | 10 GB | 20 GB |
| 网络 | 独享 IP，无共享 NAT | CN2 GIA / 直连线路 |
| 操作系统 | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |

### 2.2 域名准备

1. 购买或使用已有域名，添加 **A 记录**指向服务器公网 IP：

   ```
   remote.yourcompany.com  →  <服务器公网 IP>
   ```

2. DNS 生效通常需要 5 ~ 30 分钟，可用以下命令验证：

   ```bash
   dig +short remote.yourcompany.com A
   # 应返回服务器公网 IP
   ```

3. 确认域名可从外部解析再继续，否则 Let's Encrypt 签发证书会失败。

### 2.3 服务器初始配置

以 root 用户登录，更新系统并安装基础工具：

```bash
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git dnsutils python3
```

### 2.4 上传脚本至服务器

将整个 `vpn/` 目录上传到服务器：

```bash
# 本地执行（将 <SERVER_IP> 替换为实际 IP）
scp -r vpn/ root@<SERVER_IP>:/opt/enterprise-vpn/

# 或在服务器上直接克隆仓库
git clone <仓库地址> /opt/enterprise-vpn
```

---

## 3. 服务端安装

### 3.1 修改配置变量

**在执行安装前，必须修改以下两个变量：**

```bash
cd /opt/enterprise-vpn

# 打开 install.sh，修改顶部配置变量
nano install.sh
```

找到并修改这两行：

```bash
DOMAIN="${DOMAIN:-remote.yourcompany.com}"   # ← 改为你的实际域名
EMAIL="${EMAIL:-it-admin@yourcompany.com}"   # ← 改为 Let's Encrypt 通知邮箱
FIRST_CLIENT="${FIRST_CLIENT:-employee1}"    # ← 首个客户端名称（可选）
```

或通过环境变量传入，无需修改文件：

```bash
export DOMAIN="vpn.example.com"
export EMAIL="admin@example.com"
export FIRST_CLIENT="alice"
```

### 3.2 执行一键安装

```bash
cd /opt/enterprise-vpn
chmod +x *.sh

# 方式一：使用已修改的 install.sh
bash install.sh

# 方式二：通过环境变量传入
DOMAIN="vpn.example.com" EMAIL="admin@example.com" bash install.sh
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
  WireGuard 子网: 10.200.0.0/24

  开放端口:
    TCP 443   — Nginx HTTPS（伪装站 + WS隧道入口）
    UDP 51820 — WireGuard 直连

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
bash /opt/enterprise-vpn/06-peer-manager.sh add bob

# 查看 bob 的配置内容
bash /opt/enterprise-vpn/06-peer-manager.sh config bob

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
bash /opt/enterprise-vpn/06-peer-manager.sh qrcode bob
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
    -L "udp://127.0.0.1:51820:127.0.0.1:51820?timeout_sec=0" \
    wss://vpn.example.com/secure-tunnel/ &

# 第二步：修改 WireGuard 配置中的 Endpoint
# 将 Endpoint = vpn.example.com:51820
# 改为 Endpoint = 127.0.0.1:51820

# 第三步：连接 WireGuard
sudo wg-quick up wg0
```

**Windows（PowerShell）：**

```powershell
# 第一步：后台启动 wstunnel
Start-Process wstunnel.exe -ArgumentList `
    "client --connection-retry-max-backoff-sec 10 -L `"udp://127.0.0.1:51820:127.0.0.1:51820?timeout_sec=0`" wss://vpn.example.com/secure-tunnel/" `
    -WindowStyle Hidden

# 第二步：在 WireGuard 客户端中将 Endpoint 改为 127.0.0.1:51820，然后激活
```

---

## 5. 日常运维操作

### 5.1 员工账号管理

```bash
cd /opt/enterprise-vpn

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
  listening port: 51820

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

# WireGuard 监听 UDP 51820
ss -ulnp | grep 51820

# wstunnel 监听 TCP 2080（仅 127.0.0.1）
ss -tlnp | grep 2080

# Nginx 监听 TCP 443
ss -tlnp | grep 443
```

**第二步：从客户端侧测试连通性：**

```bash
# 测试 443 端口（HTTPS）
curl -v https://vpn.example.com/

# 测试 51820 UDP（需 netcat）
nc -u -v vpn.example.com 51820
```

**第三步：检查防火墙是否放行：**

```bash
# 确认 443 和 51820 在规则中
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
   bash /opt/enterprise-vpn/06-peer-manager.sh remove <用户名>
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

## 附录：文件结构速查

```
/opt/enterprise-vpn/
├── install.sh                  # 一键安装主控脚本
├── 01-system-tune.sh           # 内核调优（BBR、IP转发、缓冲区）
├── 02-nginx-setup.sh           # Nginx TLS + 证书 + 路径路由
├── 03-wireguard-setup.sh       # WireGuard 服务端 + 密钥轮换
├── 04-wstunnel-setup.sh        # wstunnel WebSocket 封装层
├── 05-nftables-setup.sh        # 防火墙规则（持久化）
└── 06-peer-manager.sh          # 客户端 Peer 管理

/etc/wireguard/
├── wg0.conf                    # WireGuard 服务端配置（含所有 Peer）
├── server-private.key          # 服务端私钥（chmod 600，勿外传）
├── server-public.key           # 服务端公钥
├── .wan-interface              # 检测到的 WAN 网卡名
├── client-wstunnel-guide.txt   # wstunnel 客户端使用说明
├── peers/                      # 客户端配置目录
│   ├── alice.conf              # alice 的完整客户端配置
│   ├── alice.meta              # alice 的元数据（IP、公钥、创建时间）
│   ├── alice.private           # alice 的私钥（仅服务端存留，用于导出配置）
│   └── alice.psk               # alice 的预共享密钥
└── key-backup/                 # 密钥轮换历史备份
    └── 2026-05-01_030000/
```

---

*如遇问题请检查 `journalctl -u wg-quick@wg0` 和 `journalctl -u nginx` 日志，或联系 IT 管理员。*
