# 连接故障定位教程（快速模式 / 强力模式 连不上）

> 面向：运维 / 后续开发者 / AI。
> 目标：遇到"某节点连不上 / 快速模式连不上 / 时通时断"，能**从原理出发**逐层定位，
> 知道每一步**为什么做、预期看到什么、不符合又意味着什么**。
> 原则：**先读不改**。绝大多数"连不上"是配置不一致或机房网络，而非代码 bug。

---

## 0. 先建立正确的心智模型（最重要）

客户端连一个节点，数据要穿过这几层，任何一层断都会"连不上"：

```
[App] 用 PORT_SECRET 算出"当前小时"的跳变端口(HMAC)
   │
   │ ① 直连(快速模式)：UDP → endpoint:跳变端口
   │        服务器 iptables AWG_HOP 链 REDIRECT → 本机 UDP 51820
   │
   └ ② 回退(强力模式)：WSS 443 → Nginx /secure-tunnel/ → wstunnel:2080 → 127.0.0.1:51820
                                                                    ↓
                                              AmneziaWG 接口 awg0 (UDP 51820)
                                              · server 私钥 + 客户端公钥 做握手
                                              · 混淆参数 Jc/Jmin/Jmax/S1/S2/H1-H4 两端必须一致
                                              · 该客户端的 peer(公钥+AllowedIP) 必须已在 awg0.conf
                                                       ↓ 握手成功
                                              按 AllowedIPs 路由(智能/全局) → nftables NAT → 公网
```

客户端**只有在 HTTP 204 探测真正通了之后**才显示"已连接"。直连 12 秒内没通 → 自动回退强力模式。

### 两条黄金推理（先做这两个判断，能砍掉一大半可能）

**A. 强力模式能连吗？**
- **能**：说明 awg 本身、服务器密钥、**AWG 混淆参数**、该用户的 **peer**、出口 NAT、路由**全部正常**
  （强力模式跑的是同一套 WireGuard 握手，只是包改走 443→wstunnel→51820）。
  → 问题被锁定在**①直连的 UDP 入站路径**：跳变端口 DNAT / 防火墙 / **机房是否放行入站 UDP**。
- **都不能**：问题在更底层——peer 不存在 / 密钥或混淆参数不一致 / awg 没起 / 出口不通。

**B. 同一个客户端，换个节点能连吗？**
- **别的节点快速模式能连，唯独某节点不行**：客户端网络**能发 UDP**（否则哪个都连不上直连）。
  → 是**那台服务器/那家机房**特有问题，不是客户端。
- **所有节点快速都连不上、只能走强力**：很可能是**客户端本地网络封了 UDP 高端口**
  （公司网/校园网/部分移动网常见）。这是正常现象，回退强力即为此设计，**非 bug**。

> 把 A、B 结论一组合，往往直接指向根因。例：A=强力能连 + B=只有 FRA01 不行 → 一定是 FRA01 机房的入站 UDP 问题（丢包/被封/间歇）。

---

## 1. 快速定位决策树

```
连不上？
├─ 强力模式也连不上？
│   ├─ 是 → 走【第 3 节：peer / 密钥 / 混淆参数 / awg 一致性】
│   └─ 否（强力能连，只是快速不行）→
│        同一客户端别的节点快速模式能连吗？
│        ├─ 能（只有这台不行）→ 走【第 2.3 + 第 5 节：该服务器 UDP 入站路径 + 抓包定性】
│        └─ 都不能（所有节点快速都不行）→ 客户端本地网络封 UDP（让用户换网验证）→ 正常回退强力
```

---

## 2. 服务器健康基线（任何节点先过这关）

在目标服务器上执行；**预期全绿**，否则先修这里。

```bash
# 2.1 各服务在跑
systemctl is-active nginx awg-quick@awg0 wstunnel nftables vpn-api
# 预期：5 个 active。某个 inactive → 先 systemctl restart 它。

# 2.2 awg 内部端口在监听
ss -ulnp | grep 51820 || echo "❌ awg 未监听 51820"
# 预期：0.0.0.0:51820。没有 → awg-quick@awg0 没起来 → journalctl -u awg-quick@awg0。

# 2.3 端口跳变状态（当前对外端口 + DNAT + 定时器）
bash /opt/mirrorspeed/vpn/08-port-hopping-setup.sh status
iptables -t nat -S | grep -iE "AWG_HOP|51820"
systemctl is-active awg-port-rotate.timer
# 预期：status 打印"当前生效端口"；AWG_HOP 链有 7 条 REDIRECT→51820；timer=active。
# 缺失/挂掉 → 重跑 bash 08-port-hopping-setup.sh（复用已有 PORT_SECRET，安全，不破坏客户端）。

# 2.4 vpn-api 健康 + 新接口
curl -s http://127.0.0.1:8443/health
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8443/peers/ensure
# 预期：health 返回 JSON；/peers/ensure 返回 401(鉴权,说明新代码在)。404=旧 vpn-api,需 cp main.py 重启。
```

> **原理**：iptables `REDIRECT --to-ports 51820` 把"当前小时 ±3 共 7 个跳变端口"全部转到 awg 内部固定 UDP 51820。
> 客户端用同一 `PORT_SECRET` + 同一公式算出当前端口直接连，无需协商；每小时整点 systemd timer 轮换；
> 保留 ±3 窗口是为容忍客户端深度休眠后的时钟漂移。

---

## 3. 配置一致性检查（强力都连不上 / 握手失败时）

**核心原理**：客户端配置由 Portal 用 **Supabase 登记的值**生成；服务器**本机实际值**与 DB 不一致，
客户端就拿错的参数握手，必然失败。最常见于**装失败后重做、或重跑过 03/08 脚本**的机器。

| 项 | DB 字段(vpn_servers) | 服务器本机 | 不一致后果 |
|---|---|---|---|
| 服务端公钥 | `public_key` | `cat /etc/wireguard/server-public.key` | 全失败 |
| 端口跳变密钥 | `port_secret` | `cat /etc/wireguard/.port-secret` | 客户端算的端口服务器没开 → 直连永远打不中(强力仍可能通) |
| 混淆参数 | `awg_jc/jmin/jmax/s1/s2/h1..h4` | `cat /etc/wireguard/awg-params.env` | DPI 混淆头对不上 → 握手失败(直连+强力都失败) |
| 端点域名 | `endpoint`/`api_url` | 实际域名/证书 | 连错地址/TLS 不匹配 |

DB 查询（开发机，有 `portal/.env.local`）：
```bash
SB_URL=$(grep -oE 'NEXT_PUBLIC_SUPABASE_URL=[^ ]*' portal/.env.local|cut -d= -f2-|tr -d '\r"')
SB_KEY=$(grep -oE 'SUPABASE_SERVICE_ROLE_KEY=[^ ]*' portal/.env.local|cut -d= -f2-|tr -d '\r"')
curl -s "$SB_URL/rest/v1/vpn_servers?select=name,public_key,port_secret,awg_jc,awg_h1&name=eq.FRA01" \
  -H "apikey: $SB_KEY" -H "Authorization: Bearer $SB_KEY"
```
逐项和本机比对。任一不一致 → 以本机为准 UPDATE 回 DB。

> 经验：`port_secret` 一致但直连不通、且强力能连 → 排除一致性，去第 4/5 节。
> 混淆参数不一致会让**强力也连不上**——所以"强力能连"本身就证明混淆参数是对的。

---

## 4. 按需 peer 是否存在（on-demand 架构特有）

**原理**：现在"按需建 peer"——客户端连接前调 `/api/mobile/ensure-peer`，Portal 才把该**设备全局公钥+IP**
用 `awg set` 加到 awg0.conf。没成功 → 服务器没有这个 peer → 握手被拒。

```bash
awg show awg0 | grep -A3 "peer:"      # 所有 peer 公钥 + endpoint + 最近握手 + allowed ips
awg show awg0 | grep "allowed ips"    # 该用户的 10.200.x.y 在不在
```
- **peer 不在** → ensure 没成功；让客户端重连，或查 `journalctl -u vpn-api`。
- **同一 IP 出现在两个不同公钥的 peer** → **IP 撞车**(旧全笛卡尔积残留)。WG 只把该 IP 路由给其中一个 →
  另一个握手成功但数据不通 → 直连失败回退强力。
  修复：触发 GC `curl -H "Authorization: Bearer <CRON_SECRET>" https://www.mirrorspeed.com/api/cron/gc-peers`，
  或服务器 `bash vpn/reset-peers.sh` 全清后让客户端重连重建。

---

## 5. 决定性抓包：UDP 到底有没有到达（直连失败、强力能连时）

到这一步，问题已锁定在"直连 UDP 入站路径"。**抓包一锤定音**：

```bash
bash /opt/mirrorspeed/vpn/08-port-hopping-setup.sh status | grep -E "当前生效|相邻"
# 抓 30 秒（期间让用户连这台"快速模式"）
timeout 30 tcpdump -ni any 'udp and (portrange 30000-49999 or port 51820)' -c 40
# 防火墙 INPUT 是否放行 udp 51820（REDIRECT 后包的目的端口是 51820）
nft list ruleset 2>/dev/null | sed -n '/hook input/,/}/p' | grep -iE "51820|udp|policy|drop" | head
iptables -S | grep -iE "51820|INPUT|DROP" | head
```

| 抓包结果 | 含义 | 处理 |
|---|---|---|
| 抓到该用户 IP→跳变端口的 UDP，且有双向往返 | 路径通；若仍连不上看混淆参数/MTU | 多数已恢复 |
| 抓到**入站**但**无出站回包** | 包进来了但 awg 没握手 → INPUT 丢包 / peer 不存在 / 混淆参数不一致 | 第 3、4 节 + 防火墙 |
| **完全抓不到**该用户的 UDP | 包没到服务器 → 机房封入站 UDP，或客户端封出站 UDP | 见下方判定 |

**区分机房封 vs 客户端封**：同一客户端连别的节点快速能通 → 是这台机房；连所有节点快速都不通 → 客户端本地网络。

> 机房 UDP 问题特征：强力(443/TCP)永远稳，快速(UDP)时通时断/不通；换机房或换出口可解。服务器内改不了上游防火墙。
> 在管理后台看该节点"快速模式占比"长期偏低 = 机房 UDP 差的强证据。

---

## 6. 限速会不会导致连不上？

**不会，只会限速。** tc 在 awg0 egress 按 fwmark 整形已建立隧道的下行流量，握手成功**之后**才起作用。
```bash
tc -s class show dev awg0     # overlimits 增长=在限速，但不丢握手
ipset list ms_free; ipset list ms_paid
```

---

## 7. 管理后台数据怎么看 / 常见坑

后台(`/admin`，lonzo.huang@gmail.com 登录)实时拉各节点 `/stats`+`/peers`：
- **「活跃 Peer」来自服务器 `/stats`**（服务器本地判定最近 5 分钟内握手），最权威。
- **每个 peer 的「模式」** 按 endpoint 判定：`127.0.0.1`=强力(wstunnel)，真实公网 IP=快速(直连)。
- **「快速/强力/快速率」汇总** 由后台按"在线 peer"(最近 3 分钟握手)统计。
- **每个 peer 速率** 由相邻两次刷新(30s)的 rx/tx 增量算出。

> ⚠️ **时区坑（已修，引以为戒）**：vpn-api 的握手时间**必须输出 UTC(带时区)**。
> 曾经输出"无时区的服务器本地时间(CST)"，浏览器按本地时区解析成**未来时间**，导致
> `现在-握手 < 3分钟` 误判成立 → 明明几小时前的 peer 被标成"在线"，于是出现
> **「活跃 0 但快速 3 强力 1」的矛盾 + 握手列显示负秒数**。
> 判别：**握手列出现负数** = 时区错位。修复：`datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()`。

---

## 8. 根因对照表

| 现象 | 最可能根因 | 定位/修复 |
|---|---|---|
| 强力+快速都连不上，握手失败 | 该设备 peer 不在 / 公钥或混淆参数与 DB 不一致 | 第 3、4 节 |
| 强力能连，快速对**所有**节点都不行 | 客户端本地网络封 UDP | 换网验证；正常回退强力 |
| 强力能连，快速**只某台**不行 | 那台机房封/丢入站 UDP；或该台 DNAT/INPUT 异常 | 第 2.3 + 第 5 节 |
| 快速**时通时断** | 机房 UDP 丢包；或时钟漂移超 ±3 窗口 | 第 5 节；`timedatectl` |
| 直连握手成功但**打不开网页**随即回退 | WG-in-WG 环路 / MTU 过大 | Portal 已 carve-out + MTU=1280；**重新登录**拉新配置 |
| 后台"活跃 0 但快速 N"、握手负秒数 | vpn-api 握手时间没带时区(时区坑) | 第 7 节，已修 |
| 付费却被限速 4M | ratelimit 把其 IP 分到 free（旧残留撞 IP） | GC 清残留 + ratelimit 只认 provisioned=true |

---

## 9. 命令速查

**服务器（节点）**
```bash
systemctl is-active nginx awg-quick@awg0 wstunnel nftables vpn-api
ss -ulnp | grep 51820
bash /opt/mirrorspeed/vpn/08-port-hopping-setup.sh status
iptables -t nat -S | grep AWG_HOP
awg show awg0
journalctl -u awg-quick@awg0 -n 50 --no-pager
journalctl -u vpn-api -n 50 --no-pager
cat /etc/wireguard/.port-secret ; cat /etc/wireguard/awg-params.env ; cat /etc/wireguard/server-public.key
timedatectl                       # 确认时钟/时区
timeout 30 tcpdump -ni any 'udp and (portrange 30000-49999 or port 51820)' -c 40
```

**管理后台**：https://www.mirrorspeed.com/admin （node 健康 / 每 peer 模式·速率 / 每台快速率）。

---

## 10. 组件原理附录

- **端口跳变**：`port = 30000 + HMAC-SHA256(PORT_SECRET, floor(unixtime/3600))[0:4] % 20000`。
  服务端开 current±3 共 7 个端口 DNAT→51820；客户端连接时算一次、钉死整会话。
- **AmneziaWG 混淆**：标准 WireGuard 握手包前后插 junk 包 + 改写 magic header(Jc/Jmin/Jmax/S1/S2/H1-H4)，
  对抗 DPI。两端参数必须逐字一致，否则对端认不出握手包。
- **强力模式(wstunnel)**：把 WireGuard UDP 包封进 WSS(443/TCP)，绕过 UDP 封锁；服务端 wstunnel 在
  127.0.0.1:2080 收、转发到 127.0.0.1:51820。所以强力模式下 awg 看到的 peer endpoint=`127.0.0.1`
  （后台据此判"强力"；真实公网 IP="快速"）。
- **按需建 peer**：设备一次性生成全局密钥+全局唯一 IP，连接前 `ensure-peer` 用 `awg set` 加到目标服务器；
  闲置由 `gc-peers` cron 回收。详见 `docs/on-demand-provisioning.md`。
- **限速**：app_config 三档速率；ratelimit-sync 下发各档 IP；服务器 ipset+fwmark+tc 在 awg0 egress 限下行。
  详见 README §2.1.4。
