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

## 8.1 客户端 ↔ 后端 字段约定（client 按此解析，backend 按此下发）

分工：后端(lonzo, main 主线) / 客户端 iOS+macOS(Claude)。双方以本节为准。

### 请求：客户端如何声明自己是新版

`/api/mobile/configs` 与 `/api/mobile/ensure-peer` 的请求带上：

```
app_version: "3.0.0"      // 已有字段沿用即可
caps: ["singbox"]          // 新增；后端据此决定发不发 singbox 块
```

不带 `caps` 的老客户端，后端行为**完全不变**（只发 `wg_conf`）。

### 响应：每个节点追加一个可选的 `singbox` 对象

老字段全部保留、含义不变；新增的 `singbox` 为**可空**对象，节点未开通
（`sb_enabled=false`）时整个省略，客户端自动回退 AWG。

```jsonc
{
  "id": "es01",
  "display_name": "西班牙01",
  "endpoint": "82.223.165.88",
  "wg_conf": "...",            // 老字段保留，双栈期两者同时下发
  "port_secret": "...",
  "singbox": {
    "uuid": "a1b2c3d4-...",    // VLESS 认证，reality 与 ws 共用
    "hy2_password": "...",     // Hysteria2 认证

    // 快速层。缺失 = 该节点不提供快速模式
    "hysteria2": {
      "server": "82.223.165.88",
      "port": 18443,           // sing-box 实际监听的 UDP 端口（固定）
      "ports": "30000-49999",  // 可空；端口跳跃范围，交给 sing-box 原生跳跃
      "obfs_password": "..."   // 可空；salamander 混淆密码
    },

    // 强力层。缺失 = 不提供强力模式
    "reality": {
      "server": "82.223.165.88",
      "port": 443,
      "public_key": "...",     // 节点级
      "short_id": "...",       // 节点级
      "sni": "www.microsoft.com",
      "flow": "xtls-rprx-vision"   // 可空
    },

    // 超级层（经 Cloudflare）。**阶段 2 才实施**，阶段 1 整个省略
    "ws": {
      "host": "cf.mirrorspeed.com",  // CF 代理的域名，也用作 TLS SNI 与 Host 头
      "port": 443,
      "path": "/xxxxxx"
    }
  }
}
```

### 客户端行为（已约定，后端无需关心细节）

- `singbox == null` → 走现有 AmneziaWG 路径，行为与今天完全一致；
- `singbox != null` → 用 sing-box 引擎，子对象分别对应 快速/强力/超级；
  某个子对象缺失，则该模式在 UI 上不可选。**阶段 1 只会有 hysteria2 与 reality**，
  `ws` 留到阶段 2 —— 客户端已按可空处理，阶段 2 后端开始下发即自动生效，不用发版；
- 路由复用免费节点那套：GeoSite-CN/GeoIP-CN 直连、广告域名强制走代理、干净 DNS；
- 节点级参数（reality 的 pbk/sid/sni、hy2 端口、ws path/host）**只从本接口读**，
  客户端不内置任何默认值 —— 后端改参数即时生效，不用发版。

### 两条硬约束

1. **`uuid` 与 `hy2_password` 必须按设备下发**，不同设备不同值；否则无法按设备
   统计流量与封禁，也会让"设备数上限"形同虚设。
2. **Reality 不能走 Cloudflare**（CF 终止 TLS 会让偷握手失效），所以 `ws` 层固定
   是 WS+TLS，`reality` 层必须直连节点 IP。两者的 `server`/`host` 不应相同。

---

## 9. 已定决策(2026-10-03)

### 端口跳跃：采用 sing-box 原生方案（定于 2026-10-03）

**客户端不做任何端口计算**，范围由后端下发、交给 sing-box 原生跳跃。理由：iOS 发版
要过审核，凡是可能调整的策略都不该固化进客户端，否则改个范围都得发版等审核。
WG 那套 HMAC 每小时跳的机制双栈期保持不动，sunset 时一并删除。

节点侧三件事（替代 WG 那套「7 条规则 + 每小时轮换」，不再需要定时任务）：

1. sing-box 监听 **UDP 18443**（固定单端口）；
2. nat 表整段重定向：
   `iptables -t nat -A PREROUTING -p udp --dport 30000:49999 -j REDIRECT --to-port 18443`
3. `enterprise-fw` input 链放行 **18443**（REDIRECT 发生在 filter INPUT 之前，
   放行的是改写**后**的端口，不是那段范围）。

> ⚠️ 双栈期顺序陷阱：WG 的 7 个跳变端口也落在 30000-49999 内。PREROUTING 里
> `jump AWG_HOP` 必须排在上面那条整段规则**之前** —— WG 的 7 个端口在 AWG_HOP 里
> 被 REDIRECT 到 51820（终结动作），匹配不上的才继续走到 hy2 这条。顺序反了会让
> 所有 WG 老客户端连不上。


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

## 11. 存量 AWG 节点升级为双栈（Reality 占 443，牺牲 wstunnel 强力）

决策(2026-10-04)：存量节点让 **Reality 占 443**，牺牲老客户端的 **wstunnel 强力**；
老客户端的 **AWG 快速(直连 UDP)仍保留**，不受影响。

⚠️ 关键：存量节点的 `vpn-api` 原本挂在 nginx 443 后面(`https://节点/vpn-api`)。停 nginx 前
**必须先把 vpn-api 挪到独立端口 :8443 直连 TLS 并更新 DB api_url**，否则停 nginx 会连带断掉
`/vpn-api` → 连老客户端的 AWG 发 peer 都失败。

### 每台存量节点的升级步骤(以 german01 为例，其余照做)

```bash
# ① 拉最新代码(含 vpn-api 的 /singbox 接口)
cd /opt/mirrorspeed && git pull

# ② vpn-api 改为独立 TLS :8443(复用该节点已有证书)。先找到证书域名：
DOMAIN=$(ls /etc/letsencrypt/live/ | grep -m1 'mirrorspeed\.com')
# 读出该节点现有的 VPN_API_SECRET(保持不变，全节点通常共用)
grep VPN_API_SECRET /opt/mirrorspeed/vpn-api/.env
# 改 systemd 让 uvicorn 直接上 TLS、对外 8443：
cat > /etc/systemd/system/vpn-api.service <<EOF
[Unit]
After=network.target
[Service]
WorkingDirectory=/opt/mirrorspeed/vpn-api
EnvironmentFile=/opt/mirrorspeed/vpn-api/.env
ExecStart=/opt/mirrorspeed/vpn-api/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8443 \
  --ssl-certfile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem \
  --ssl-keyfile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl restart vpn-api
# 安全组放行 TCP 8443

# ③ 更新 DB：api_url 指向 :8443（这样 AWG 和 sing-box 发凭证都走新端口，AWG 不断）
#    Supabase SQL：
#    UPDATE vpn_servers SET api_url='https://<该节点域名>:8443/' WHERE name='<node>';

# ④ 部署 sing-box（停 nginx 让 Reality 占 443，复用已有证书，AWG 不动）
sudo STOP_NGINX=1 DOMAIN=${DOMAIN} EMAIL=admin@mirrorspeed.com bash vpn/04-singbox-setup.sh
# 安全组放行 UDP 30000-49999 和 18443

# ⑤ 把脚本打印的参数写回 DB：sb_enabled=true（awg_enabled 保持 true 不改！），
#    reality_pbk/sid/sni、reality_port=443、hy2_port/hop、api_secret 保持该节点原值。
```

升级后该节点：老客户端 **AWG 快速仍可用**（AWG 未动 + 发 peer 走 :8443）；老客户端 wstunnel
**强力失效**(已接受)；新客户端走 **sing-box(reality 443 / hy2)**。双栈并存。
