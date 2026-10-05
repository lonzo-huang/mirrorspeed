# AGENTS.md — MirrorSpeed VPN 工程手册

> 给在本仓库工作的 AI agent / 新同学的「先读这一篇」。涵盖：模块地图、架构数据流、
> 如何部署、如何发包、如何调优、开发注意事项与踩过的坑。
> 细节文档在 `docs/`，本文件是索引 + 不写在代码里的约定。

---

## 0. 产品与命名约定（硬性）

- 商业 VPN。英文名 **MirrorSpeed VPN**，中文壳「**镜速加速器**」。
- 仓库：`github.com/lonzo-huang/mirrorspeed`，**主分支 `main`**（不是 master）。
- **对外一切**（服务名、目录、日志、二进制、UI）统一用 **MirrorSpeed**，不出现 `awg`/`amneziawg`。
- **中文壳不出现「VPN」字样**（合规），用「加速器」。
- git 提交署名：`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 工作习惯：**改完代码立即 commit+push 到 main，不等用户问**（见 memory `feedback_always_commit`）。

---

## 1. 模块地图

| 目录 | 技术栈 | 职责 | 部署在哪 |
|---|---|---|---|
| `client/` | Flutter (Dart) | Android/Windows/iOS/macOS 客户端 | 用户设备 |
| `portal/` | Next.js 14 + TypeScript | 官网 + 移动端 API + 计费 + 博客 + cron | **Vercel**（推 main 自动部署）|
| `vpn/` | Bash + Python | 单节点部署脚本（01→11）+ 控制机同步程序 | 每台 VPS（Ubuntu 22.04/24.04）|
| `vpn-api/` | FastAPI (Python) | 每节点管理 API（peer/singbox 下发、状态）| 每台 VPS，`:8443` TLS |
| `portal/supabase/migrations/` | SQL | 数据库 schema/RLS/RPC | **Supabase**（Postgres）|
| `wp-theme/`, `icon/` | — | 旧 WP 主题、图标资源 | — |
| `docs/` | Markdown | 架构/迁移/排障文档 | — |

### 1.1 client/lib 子模块
- `providers/`：`vpn_provider.dart`（优质节点连接状态机，核心）、`shared_node_provider.dart`（免费机场）、`auth_provider.dart`。
- `vpn/`：`proxy_core_engine.dart`（sing-box 引擎，MethodChannel `mirrorspeed/singbox`）、`singbox_config.dart`（生成 sing-box 配置：路由/DNS/分流）、`singbox_windows_runner.dart`（桌面子进程）、`vpn_engine.dart`（接口 + `VpnStage`/`EngineKind`）。
- `models/`：`singbox_premium.dart`（优质节点协议参数契约）、`server_config.dart`、`free_node.dart`。
- `services/`：`api_service.dart`（调 portal，带域名 failover）、`ad_service.dart`（AdMob）、`iap_service.dart`（内购）、`app_proxy_store.dart`（分应用）、`port_hopping.dart`、`ws_relay_service.dart`、`free_node_service.dart`、`desktop_tray.dart`。
- 原生 sing-box：`packages/singbox_flutter/`（插件）、`android/.../kotlin/.../`（VpnService）、`ios_macos_native/SingboxTunnel/`（NEPacketTunnelProvider）。
- 智能分流资源：`assets/routes/cn_cidr.txt`（约 106 条 CN CIDR，非 Apple 用）；Apple 用打包的 `.srs` rule_set。

### 1.2 portal API 路由（`portal/src/app/api/`）
- 移动端：`mobile/configs`（下发节点+凭证）、`mobile/ensure-peer`（按需 provision）、`mobile/device`、`mobile/referral`。
- 计费：`billing/*`、`webhooks/stripe`、`iap/apple/*`。
- 展示/下载：`servers`、`releases/latest`、`download`、`announcement`、`geo`。
- 管理：`admin/*`、`blog/*`、`refund`、`support`。
- **cron**（见 §5）：`cron/check-subscriptions`、`cron/gc-peers`、`cron/gc-refund-blobs`、`cron/collect-stats`。

### 1.3 节点脚本执行顺序（`vpn/install.sh` 编排）
`01-system-tune` → `02-nginx-setup` → `03-amneziawg-setup` → `04-wstunnel-setup` →
`05-nftables-setup` → `08-port-hopping-setup` → `06-peer-manager`(建首个 peer) →
`07-vpnapi-setup` → `09-ratelimit-setup`。
另有：`04-singbox-setup.sh`（**sing-box 双栈，存量升级核心**）、`10-system-optimize`、
`11-sync-servers-setup`（控制机状态同步，见 §5）、`fix-cert.sh`/`fix-subnet-acl.sh`/`reset-peers.sh`。

---

## 2. 架构数据流（必须理解）

**三种协议 / 三个模式**（优质节点，sing-box）：
| 模式 | 协议 | 端口 | 抗封锁 |
|---|---|---|---|
| 快速 | Hysteria2 (UDP/QUIC, salamander obfs) | 监听 UDP 18443，客户端在 50000-60000 跳跃(nft 重定向到 18443) | 高(QUIC 国内偶被限速) |
| 强力 | VLESS + Reality (TCP) | **标准 443**，与 nginx 共用(Reality 回落) | 最高(伪装成普通 HTTPS) |
| 超级 | VLESS+WS+TLS 经 Cloudflare | 443/CF | 阶段 2，未开 |

**双栈兼容**：存量节点同时跑 AWG(老客户端)和 sing-box(新客户端)。后端按 `vpn_servers.awg_enabled`/
`sb_enabled` 下发：老客户端拿 `wg_conf`，纯 sing-box 新客户端拿 `singbox` 块。**不做版本门控**。

**Reality 占 443 + nginx 回落**（`NGINX_FALLBACK=1`）：nginx 从公网 443 挪到 `127.0.0.1:8080`，
Reality 占 443 并把「非 Reality 流量」（老客户端健康探测 / wstunnel 强力 / 普通 HTTPS）透明回落给
本机 nginx → 老客户端零影响。

**按需 provision（on-demand）**：
1. 客户端连接前/打开节点列表时调 portal `POST /api/mobile/ensure-peer`。
2. portal（Vercel 服务端）从 DB 读节点 `api_url`+`api_secret`，**直连节点 `https://<域名>:8443`**：
   - `awg_enabled!==false` → `POST /peers/ensure`（幂等，推 client 公钥，不生成密钥）；
   - `sb_enabled` → `POST /singbox/user/ensure`（把设备 UUID+hy2 密码写进 `/etc/sing-box/config.json` 的 users 并 reload）。
3. 设备密钥由 portal `device-crypto.ts` 的 `ensureDeviceCrypto` 生成（每设备一份全局 WG 密钥对 + `sb_uuid` + `hy2_password`，存 `vpn_devices`）。
4. **顺序坑**：ensure-peer 先 AWG 后 singbox，AWG 失败会 `return` 短路 singbox（见 §7）。

---

## 3. 部署

### 3.1 全新节点
```bash
# VPS 上(Ubuntu 22.04/24.04 root)
cd /opt/mirrorspeed && git pull
DOMAIN=<域名> EMAIL=admin@mirrorspeed.com VPN_API_SECRET=<密钥> bash vpn/install.sh
```
干净节点直接开 sing-box：`DOMAIN=<域名> bash vpn/04-singbox-setup.sh`（Reality 占 443，无需 NGINX_FALLBACK）。

### 3.2 存量节点双栈升级（一步到位）
**完整流程 + 全部踩坑见 [docs/singbox-existing-node-upgrade.md](docs/singbox-existing-node-upgrade.md)。** 摘要：
```bash
cd /opt/mirrorspeed && git pull           # 含合并版 vpn-api + 修好的 04
NGINX_FALLBACK=1 HOP_MIN=50000 HOP_MAX=60000 \
  NODE_NAME=<大写DB name> DOMAIN=<该节点域名> bash vpn/04-singbox-setup.sh
```
脚本自动：挪 nginx→8080、Reality 占 443、写 sing-box 配置、放行防火墙、重启 sing-box、
**重启 vpn-api 并校验 `/peers/ensure` 非 405**、打印现成 UPDATE SQL（含真实 obfs + `api_url=:8443` + api_secret）。
把 SQL 贴 Supabase 执行，**确认 1 row affected**。

**DB name 必须大写精确匹配**：`US01 / FRA01 / ES01 / DE02 / HK01 / JP01 / SG01`（us02 小写，已开通）。
域名映射：german01→FRA01、spain01→ES01（域名是 `mirrorquant.com`）。

### 3.3 portal（Vercel）
推 `main` 自动部署。改了 `mobile/*`、`device-crypto` 等**务必确认 Vercel 实际部署版本 ≥ 该提交**
（排查 provision 问题时先看 vpn-api 日志有没有 Vercel 来的 POST）。

### 3.4 数据库（Supabase）
迁移在 `portal/supabase/migrations/`，按文件名顺序在 Supabase SQL Editor 执行。
sing-box 相关：`20261003_singbox_migration.sql`（vpn_servers 加 sb_enabled/awg_enabled/reality_*/hy2_*/ws_*）、
`20261004_singbox_device_creds.sql`（vpn_devices 加 sb_uuid/hy2_password_enc）。

### 3.5 控制机状态同步（替代 Vercel 高频 cron）
仅在**一台**机器装（需 Supabase service_role key，权限 600）：
```bash
SUPABASE_SERVICE_KEY='<service_role>' bash vpn/11-sync-servers-setup.sh
```
每 60s 探所有 active 节点 `/stats /health /peers`，回写状态、同步流量、暂停/恢复超额免费用户。
程序：`vpn/sync-servers/ms-sync-servers.py`、排障 `ms-diagnose.py`。

---

## 4. 发包（client）

- **正式发布**（Windows 上）：`client/release.ps1 <版本>`。读 `$env:MS_SUPABASE_ANON`、`$env:MS_CRON_SECRET`，
  注入 dart-define（SUPABASE_URL/ANON_KEY/API_BASE），产 **split-per-abi APK + AAB + Windows zip**，
  bump 版本、打 tag、建 GitHub Release、刷新 CN 镜像。参数：`-SkipAndroid`/`-SkipWindows`/`-DryRun`/`-WindowsOnly`。
  密钥存 `client/.release-secrets.local`（gitignore；见 memory `reference_ms_release_secrets`）。
- **iOS/macOS**：用户在 Mac 上打（`feat/ios-macos` → main）。
- **测试包**（不发布、不打 tag）：在 `client/` 下
  ```bash
  set -a; source .release-secrets.local; set +a
  flutter build apk --release --split-per-abi --no-tree-shake-icons \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=API_BASE="$API_BASE" --dart-define=AD_TEST=true
  ```
  产物在 `client/build/app/outputs/flutter-apk/`（arm64 真机装 `app-arm64-v8a-release.apk`）。
  `AD_TEST=true` 用 AdMob 测试广告位（`lib/env.dart` 的 `kAdTestMode`）。
- 当前 `pubspec.yaml` 版本 `2.6.3+93`。
- **签名**：`client/android/key.properties` + `android/app/mirrorspeed-release.jks`（已配，release 自动签名）。

---

## 5. 自动程序 / cron

- **Vercel cron**（`portal/vercel.json`）：
  - `check-subscriptions` 每天 02:00；`gc-peers` 每天 03:30（清理孤儿/陈旧 peer）；`gc-refund-blobs` 每天 04:00。
  - 鉴权用 `CRON_SECRET`。
- **控制机 cron**（§3.5）：`collect-stats` 类的高频节点探测已从 Vercel 搬到自建 `11-sync-servers`，省 Vercel 开销。

---

## 6. 调优

- **连接提速**：连接前的 `ensurePeer` 已改为**后台非阻塞**（`vpn_provider.connect`）——它往返 Vercel 数秒、
  且列表页已预热 provision，阻塞在关键路径上纯浪费。计时日志：logcat 搜 `配置就绪耗时`/`引擎 start 返回`。
  若仍慢，候选：并行化配置构建、DNS 冷启动（首个域名解析等代理 DNS 建起）、tun `stack: system`（替 gvisor）。
- **分流颗粒度**（`singbox_config.dart`）：sing-box 规则引擎按 域名(domain_suffix)/IP(ip_cidr)/进程(process_name)/
  rule_set 组合匹配，远细于 AWG 的纯 AllowedIPs。广告域名强制走代理（解决国内直连 AdMob 被墙）。
  **sing-box 1.12+ 删了内置 geoip/geosite**：Apple 用打包 `.srs`（域名+IP 级），安卓/Windows 用 `cn_cidr.txt`（仅 IP 级）。
- **端口跳跃**：hy2 范围避开 AWG 的 30000-49999，用 50000-60000；sing-box `server_ports` 用冒号 `"50000:60000"`。

---

## 7. 开发注意事项 / 已知坑（高频，排查先看这里）

1. **`vpn_servers.name` 区分大小写**，且 ≠ 域名前缀。SQL `WHERE name` / 脚本 `NODE_NAME` 必须用大写 DB name，
   否则 UPDATE 0 行、`sb_enabled` 不变、新客户端连不上。见 memory `project_vpn_servers_name_casing`。
2. **两份 `main.py` 曾分裂**：`vpn/vpn-api/main.py`（07 部署源）与 `vpn-api/main.py`（顶层）。已合并统一，
   两份都须含 `/peers/ensure`+`/peers/remove`+`/singbox/user/ensure|remove`。改动两份保持一致。
   见 memory `project_vpnapi_two_mainpy`。
3. **存量节点 `api_url` 用 `https://<域名>:8443`（无尾斜杠，直连 vpn-api）**，不要经 nginx 的 `/vpn-api`
   （nginx 以 http 反代 https 的 8443 会 502 → portal provision 失败 → 新客户端"已连接上不了网"）。
4. **`git pull` 后必须 `systemctl restart vpn-api`**，否则跑旧代码（缺 `/peers/ensure` → 405 → 短路 singbox 下发）。
5. **Reality 参数每次跑 04 都会重新生成**，只用最后一次打印的 SQL，别混用旧 `reality_pbk`。
6. **hy2_obfs 必须下发真实值**（服务端强制 salamander obfs），SQL 里不能是 NULL。
7. **"已连接但上不了网"** 的两类根因：① Reality 握手失败 `processed invalid connection`=pbk/short_id/SNI 不符；
   ② 握手过但 `unknown UUID`/hy2 密码不符=设备凭证没 provision（查 vpn-api 日志有没有 Vercel 的 `POST /singbox/user/ensure` 200）。
8. **防火墙**（`table inet enterprise-fw` policy drop）要放行 `tcp 8443`、`udp 18443`、`udp 50000-60000`；
   04 的 `ufw` 分支对 nftables 节点无效。
9. **证书**：hy2 需 TLS 证书；04 自动复用本机 `*.mirrorspeed.com` LE 证书。各节点用**自己的**域名，别照抄示例。
10. **设备凭证只由 portal 自动下发**，别手动加 sing-box 用户（手动加的测试用户确认正常后可删）。
11. **提交 & 署名**：改完即 commit+push main；署名见 §0。

---

## 8. 进度与待办

**已完成**：免费机场(sing-box libbox)、优质节点 sing-box 迁移（纯 sing-box 新客户端重构 + 双栈后端 +
Reality/hy2 端到端）、存量节点双栈升级流程（US01 已验证跑通）、按需 provision 全链路、连接提速（ensurePeer 非阻塞）。

**待办**：① 剩余 6 台节点（FRA01/DE02/HK01/JP01/SG01/ES01）按 §3.2 批量升级；
② 超级层（VLESS+WS over Cloudflare）阶段 2；③ iOS 真机验证（Mac）；④ 首连延迟进一步优化；
⑤ Google Play Billing；⑥ 2 个月后移除各节点 AWG（纯 sing-box）。

> 相关文档：`docs/singbox-migration.md`（总方案）、`docs/singbox-existing-node-upgrade.md`（存量升级+踩坑）、
> `docs/dual-engine-architecture.md`、`docs/on-demand-provisioning.md`、`docs/troubleshooting-connectivity.md`。
