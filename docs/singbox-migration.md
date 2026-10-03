# 优质节点迁移 sing-box 多协议方案

> 把优质节点从 **AmneziaWG(WG+混淆)** 迁到 **sing-box 原生多协议**,全平台统一一个引擎。
> 决策(2026-10-03):
> - 三层协议:**快速=Hysteria2 / 强力=VLESS+Reality / 超级=VLESS+WS+TLS(经 Cloudflare)**
> - 节点部署由 **lonzo** 执行(按本文脚本一台台跑)
> - 服务端**双栈兼容老客户端 2 个月**(至 ~2026-12-03),之后彻底删掉 AWG 及混淆
> - 客户端/Vercel/vpn-api 代码由 Claude 负责

---

## 1. 为什么迁

WG 只能**按 IP 路由**,做不了按域名/按进程/按应用分流,由此衍生出一连串 hack 和坑:
- Windows 优质节点无法按应用分流(需 WFP 内核驱动);
- 智能模式 DNS 走直连被污染(靠强制海外 DNS 兜);
- 广告(AdMob/GMS)路由只能靠 IP 段覆盖,极不稳;
- Apple 端还要再移植一套 AmneziaWG(gomobile)。

sing-box 一次性解决:**按应用 / 按域名(GeoSite)/ GeoIP / 广告域名强制代理 / 干净 DNS 全平台可用**,免费节点已验证这套;优质迁过来后砍掉 amneziawg 引擎,**包更小、Apple 不用移植 WG、三端一套代码**。

## 2. 目标架构(三层,对应现有"快速/强力/超级")

| 模式 | 协议 | 传输/端口 | 作用 | 对应现状 |
|---|---|---|---|---|
| 快速 | **Hysteria2** | UDP/QUIC(高端口 + 端口跳跃 + salamander 混淆) | 求快;弱网体验好 | 直连 AWG |
| 强力 | **VLESS + Reality** | TCP 443(偷真实大站 TLS 握手,无需证书) | 抗 DPI 最强,直连节点 | wstunnel 443 |
| 超级 | **VLESS + WS + TLS** | 经 **Cloudflare** 代理(CF 的 CDN IP) | 节点真实 IP/域名被封也能活 | Cloudflare Tunnel |

> ⚠️ 关键技术点:**Reality 不能走 Cloudflare**(CF 会终止/重建 TLS,Reality 的偷握手机制失效)。所以 CF 那层必须用 **WS+TLS**,不是 Reality。

每台节点用**一个 sing-box 进程**同时起 3 个 inbound。客户端用 sing-box 的 selector / urltest outbound 组做手动选择 + 自动故障切换(比现在手写的编排简单得多)。

## 3. 凭证模型(按用户发)

- **每设备一个 UUID**:vless-reality 与 vless-ws 共用(VLESS 用 UUID 认证);
- **每设备一个 hy2 密码**:Hysteria2 用密码认证(可由 UUID 派生,或独立生成);
- Reality 的 `public_key(pbk)` / `short_id(sid)` / 伪装 `sni` 是**节点级**参数(全节点用户共享,非按用户);
- WS 层的 `path` / CF 的 `host` 也是节点级。

映射到现有 `ensure-peer`:现在是「生成 WG keypair → 远程 `awg set 公钥`」,改为「生成 UUID+hy2密码 → 远程把该用户加进 sing-box 各 inbound 的 users → reload」。

## 4. 各组件改动

### 4.1 节点服务器(lonzo 执行)
新增 `vpn/04-singbox-setup.sh`(与现有 `03-amneziawg-setup.sh` **并存**,不动 AWG):
- 安装 sing-box;
- 生成 Reality 服务端 keypair(`sing-box generate reality-keypair`)、选一个伪装目标 SNI(如 `www.microsoft.com` / `www.apple.com`);
- 写 sing-box 服务端配置,3 个 inbound:
  - `hysteria2`:监听高 UDP 端口(可配端口跳跃范围)+ obfs 密码;
  - `vless`+`reality`:监听 TCP 443(若 443 被 nginx 占,用 reality 的 fallback/另起端口,或让 nginx SNI 分流);
  - `vless`+`ws`+`tls`:监听一个内部端口,前面 nginx/CF 反代 ws;
- users 初始为空,由 vpn-api 动态写入;
- 证书:Reality 不需要证书;ws+tls 走 CF 则由 CF 管 TLS(Full),或节点 nginx 用现有 `*.mirrorspeed.com` 证书;
- `systemctl enable --now sing-box`。

> 端口/伪装 SNI/Reality 密钥/CF host 这些节点级参数,跑完脚本后**写回 Supabase `vpn_servers`** 对应新列(见 4.4)。

### 4.2 vpn-api(`vpn-api/main.py`,Claude 改)
- 新增 `POST /singbox/user/ensure`:入参 `{uuid, hy2_password, name}` → 把该用户加进 sing-box 配置的 3 个 inbound 的 users 列表 → 原子写文件 + `systemctl reload sing-box`(或 sing-box 热重载);幂等。
- 新增 `POST /singbox/user/remove` / 配额挂起:从 users 移除或禁用。
- 保留现有 `/peers/ensure`(AWG)**不动**,双栈期并行。
- `/stats` `/health` 增加 sing-box 侧(可选)。
- 动态 user 管理实现二选一:①直接改 sing-box config json 的 users 数组 + reload(通用);② Hysteria2 用 HTTP 外部认证(更适合动态),VLESS 仍需写进 config。文档实现时以 ① 为主、hy2 可选 ②。

### 4.3 Vercel API(Claude 改)
- **`/api/mobile/ensure-peer`**:双栈期**同时**(a)建 AWG peer(现逻辑,给老客户端)+(b)调 `/singbox/user/ensure` 发 UUID/hy2 密码(给新客户端)。UUID/密码存库(见 4.4)。
- **`/api/mobile/configs`**:按**客户端版本/能力位**分流下发:
  - 老客户端(< 3.0 或不带 `caps=singbox`)→ 返回现有 `wg_conf`(完全不变);
  - 新客户端 → 返回 **sing-box outbound 三件套**(hy2 / vless-reality / vless-ws),含节点级 reality pbk/sid/sni、hy2 端口+obfs、ws path+cf host,以及该用户 UUID/hy2 密码。
  - 版本判定:客户端在 `registerDevice` / configs 请求里带 `app_version` 或 `caps`(新增,见 4.5)。
- 响应结构新增 `protocol` / `outbounds` 字段;老字段保留。

### 4.4 Supabase(Claude 出 migration SQL,lonzo 在 Supabase 跑)
- `vpn_servers` 新增节点级列:
  `sb_enabled bool`、`reality_pbk`、`reality_sid`、`reality_sni`、`hy2_port`、`hy2_obfs`、`ws_path`、`cf_host`(可空,无 CF 则不发超级层)。
- 用户凭证:`vpn_device_peers` 增 `uuid`、`hy2_password`(或新表 `vpn_device_singbox`)。沿用现 `device_id,server_id` 维度。
- `awg_*` 列保留,双栈期不动;sunset 时再删。

### 4.5 客户端(Claude 改)
- `registerDevice`/`configs` 请求带上 `app_version`(或 `caps=singbox`),让后端识别新客户端。
- `ServerConfig` 模型:新增可选的 sing-box outbound 三件套字段;`wgConf` 变为老路径可选。
- `vpn_provider`(优质):
  - 新客户端 + 节点支持 sing-box → 用 **SingboxConfig** 组装(hy2/reality/ws 作为 outbound,selector/urltest 分组对应 快速/强力/超级),交给现有 sing-box 引擎(`SingboxVpnService`/`SingboxWindowsRunner`/libbox)运行;
  - 复用免费节点那套路由:GeoIP-CN + GeoSite-CN 直连、按应用(package/process)、广告域名强制代理、干净 DNS —— **这些自动全平台生效**;
  - 节点不支持 sing-box(老节点)或后端仍发 wg_conf → 回退现有 AmneziaWG 路径。
- 优质/免费最终都走 sing-box,`onNeedStopOther` 互斥逻辑简化为一个引擎。
- amneziawg 引擎**双栈期保留**,sunset 后删(连带缩包)。

## 5. 灰度步骤(顺序)

1. **Supabase 加列**(4.4 SQL)——不影响线上。
2. **vpn-api 加 sing-box 接口**(4.2)——部署到一台**试点节点**。
3. **试点节点**跑 `04-singbox-setup.sh`(4.1),参数写回 `vpn_servers`,`sb_enabled=true`。
4. **Vercel** ensure-peer/configs 加双栈逻辑(4.3)——老客户端零感知(版本门控)。
5. **客户端**出一个 **3.0 测试版**:优质走 sing-box,只对 `sb_enabled` 节点生效,否则回退 AWG。真机验证试点节点的 快速/强力/超级 + 按应用 + 广告。
6. 验证 OK → 其余节点逐台跑 `04-singbox-setup.sh` + `sb_enabled=true`。
7. **发布 3.0 正式版**。此时:新用户走 sing-box,老客户端继续 AWG,**双栈并行**。
8. **观察 2 个月**(至 ~2026-12-03),看老客户端占比降到可接受。

## 6. Sunset(~2026-12-03 之后)

1. 确认老客户端(AWG)活跃占比足够低;
2. 节点上停 AWG inbound,卸载/禁用 amneziawg(保留还是直接删看你);
3. Vercel ensure-peer/configs 去掉 AWG 分支;
4. Supabase 删 `awg_*` 列;
5. 客户端下个版本删 amneziawg 引擎(缩包)。

## 7. 回滚

任一阶段出问题:
- 客户端 `sb_enabled` 读的是节点级开关 → **把该节点 `sb_enabled` 置 false**,客户端即回退 AWG,无需发版;
- Vercel 版本门控可随时只给 wg_conf;
- 双栈期 AWG 全程在线,是天然回滚底座。

## 8. 分工 & 待办

| 项 | 负责 | 状态 |
|---|---|---|
| 迁移方案(本文) | Claude | ✅ |
| Supabase migration SQL | Claude 出 / lonzo 跑 | ⬜ |
| `vpn/04-singbox-setup.sh` | Claude 出 / lonzo 跑 | ⬜ |
| vpn-api sing-box 接口 | Claude | ⬜ |
| Vercel ensure-peer/configs 双栈 | Claude | ⬜ |
| 客户端 3.0(优质走 sing-box) | Claude | ⬜ |
| 试点节点验证 | lonzo | ⬜ |
| 全节点铺开 | lonzo | ⬜ |
| 2 个月后 sunset | 双方 | ⬜ |

## 9. 已定决策(2026-10-03)

- ✅ **Reality 伪装 SNI**:默认 `www.microsoft.com`,**节点级可配置**(`vpn_servers.reality_sni`,为空则用默认)。
- ✅ **hy2 端口跳跃范围**:**30000-49999**,与现有 WG 端口跳跃同一范围(见 `08-port-hopping-setup.sh`)。hy2 服务端监听一个固定 UDP 端口,iptables DNAT 把 30000-49999 重定向过去(复用现有机制)。
- ✅ **本期范围(阶段 1)= 只做 快速(hy2)+ 强力(reality)两层**。**超级层(CF-ws)本期不真正实施**,只在 Supabase 预留 `ws_path`/`cf_host` 列(可空)、客户端/后端预留字段,**留到阶段 2 再开发部署**。
- 其余(Apple/Google 内购核验路由、客户端 3.0 版本号)与本迁移解耦,后续单独处理。

## 10. 节点侧待解决(写部署脚本前需确认)

- **443 端口占用**:现有 `02-nginx-setup.sh` 让 **nginx 占了 443**(静态站 + `/secure-tunnel/` wstunnel)。而 **VLESS+Reality 要独占 TCP 443** 才像正常 HTTPS。三选一:
  1. Reality 监听 443,把 nginx 静态站/wstunnel 挪到别的端口或由 Reality 的 fallback 接管(推荐,最像真站);
  2. Reality 用非 443 端口(抗封效果打折,不推荐);
  3. 试点阶段先在一台**干净节点**上只跑 sing-box(hy2+reality),不与旧 nginx/AWG 混部,验证通了再定混部方案。
- 建议**试点用方案 3**(干净节点),跑通再决定存量节点怎么与 nginx/AWG 共存。
