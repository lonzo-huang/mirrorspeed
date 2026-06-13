# 架构方案：按需建 Peer + /16 子网（On-Demand Provisioning）

> 状态：**设计待评审**（未动代码）
> 目标读者：后续开发者 / AI
> 关联：限速（ipset 因"IP 全局一致"而简化）、智能/手动选节点（依赖"切节点要快"）

---

## 1. 背景与问题

**现状（全笛卡尔积）**：用户每次拉 `/api/mobile/configs` 时，系统在**每一台 active 服务器**上都建一个 peer。

- 10000 用户 × 10 服务器 → **每台 10000 个 peer**（不是 1000）。
- 每台子网 `10.200.0.0/21` ≈ **最多 2046 个 IP** → 实际**到 ~2000 用户就分配不出 IP**，根本到不了 1 万。
- 单接口上万 peer：握手 CPU/内存压力、config 臃肿。

**目标**：均匀分布下**每台只装"实际用过它的人"≈ 1000/台**，且切节点依旧"点了就连上"。

---

## 2. 核心设计

### 2.1 设备密钥对 + IP 全局只分配一次（跨服务器复用）

- 每个**设备**（不是用户——一个用户可多设备）在**首次注册时**生成一对密钥 + 分配**一个全局唯一内网 IP**（`/16` 内）。
- 这套 `(privkey, pubkey, vpn_ip)` **在所有服务器上复用**：设备张三的手机在 A/B/C 任意服务器上都是同一个 `10.200.5.21` + 同一公钥。

**为什么这是点睛之笔**：
- 客户端**本来就握有自己的私钥和 IP**，能为任意节点**立刻拼出完整 WG 配置**（只差"服务器接受这个公钥"）。
- 在某台服务器"建 peer"退化成一句 `awg set <pubkey> allowed-ips <ip>`（**不生成密钥**，<100ms）。
- 限速 ipset 因 IP 全局一致而更简单（一个设备到处同 IP）。

⚠️ **per-device，不是 per-user**：同一用户两台设备 = 两个 IP，否则连同一节点会撞 IP。

### 2.2 按需建 Peer（不再全笛卡尔积）

只在"需要"时把设备加到某台服务器：
- **连接时**：客户端 connect(server) 前，若该服务器还没这个 peer，调一次"ensure peer"（快）。
- **打开节点列表时批量预热**：一次 API 调用，把**列表里所有节点**的 peer 都 `awg set` 好（并发）。等用户点哪个都是现成的 → 替代了"UDP/Realtime 手势预判"，无需实时基础设施。
- **启动时预热**：只预热"上次用的 + 智能推荐最低延迟"的 1–2 台。

### 2.3 闲置回收（GC）

- cron 定期把**N 天（如 14 天）没握手**的 peer 从服务器移除（`awg set <pubkey> remove`）。
- **DB 记录保留**（`vpn_device_peers.is_active=false` 或标记 `provisioned_on_server=false`），设备回来时再 `awg set` 秒加。
- 保持每台 awg0 精简。

---

## 3. 新数据模型

### 3.1 集中 IP 分配（并发安全）

`/16` = `10.200.0.0/16`，可用约 **65000 个 IP**（全机群共享 → 全局设备上限 ~6.5 万；以后放大 `/15` 即可）。

```sql
-- 每设备一个全局唯一 IP（一次性分配，跨服务器复用）
ALTER TABLE vpn_devices
  ADD COLUMN vpn_ip      inet,         -- 如 10.200.5.21（不带 /32）
  ADD COLUMN public_key  text,         -- 设备公钥（一次性生成）
  ADD COLUMN private_key_enc text;     -- 加密私钥（一次性生成）

-- 唯一约束，防撞
CREATE UNIQUE INDEX vpn_devices_vpn_ip_key ON vpn_devices (vpn_ip) WHERE vpn_ip IS NOT NULL;
```

**分配算法（避免并发撞号）**：用 Postgres 函数 + 行锁 / 序列：
- 方案 A（序列）：`seq` 从 2 自增，`ip = 10.200.0.0 + seq`（跳过 .0/.1/广播）。简单，但删除不回收。
- 方案 B（推荐）：一张 `ip_pool(ip, device_id nullable)` 预填或动态，`SELECT ... FOR UPDATE SKIP LOCKED LIMIT 1` 取第一个空闲。可回收。
- 起步用 A（序列到 6.5 万够久），回收需求出现再换 B。

### 3.2 Peer 与服务器的关系（哪台已 provisioned）

现有 `vpn_device_peers(device_id, server_id, ...)` 改为**记录"该设备在该服务器上的 provision 状态"**，而非每台都预建：
```sql
ALTER TABLE vpn_device_peers
  ADD COLUMN provisioned   boolean DEFAULT false,   -- 服务器上是否已 awg set
  ADD COLUMN last_seen_at  timestamptz;             -- 最近握手（GC 用）
```
密钥/IP 不再存这里（移到 `vpn_devices`，全服务器共享）。`vpn_device_peers` 退化为"设备×服务器"的 provision 台账。

> 迁移期可保留旧列，逐步切换。

---

## 4. 接口变更（Portal）

| 端点 | 作用 |
|---|---|
| `POST /api/mobile/device`（已有，改） | 注册设备时**分配 IP + 生成密钥对**（一次性） |
| `GET /api/mobile/configs`（改） | 不再全笛卡尔积建 peer；只返回**节点列表 + 该设备的 privkey/IP**，客户端据此自行拼配置 |
| `POST /api/mobile/ensure-peer`（新） | body: `{device_id, server_ids[]}`；在指定服务器上 `awg set` 该设备（连接前/列表预热调用），幂等 |
| `POST /api/cron/gc-peers`（新） | 定期回收闲置 peer（vpn-api 查 `awg show dump` 的 latest-handshake，移除 N 天未握手的） |

vpn-api（服务器）新增/确认：
- `POST /peers/ensure` — `awg set <pubkey> allowed-ips <ip>/32`（已有 peer 则幂等）。比现有 `POST /peers`（生成密钥）更轻。
- `DELETE /peers/<pubkey>` 或 `POST /peers/remove` — `awg set <pubkey> remove`（GC 用）。

---

## 5. 服务器变更

1. **子网 → `/16`**：`03-amneziawg-setup.sh` 的 `AWG_SUBNET=10.200.0.0/16`、`AWG_SERVER_IP=10.200.0.1`；nftables/iptables NAT 段同步改 `/16`。
2. **现有 3 台重配**：当前只有 employee1 + 少量测试 peer，重建无痛（改子网 → 重启 awg-quick → 重新 provision）。
3. **peer 命名**：`ms-<device_id>`（跨服务器一致，不再带 server）。
4. vpn-api 增加 `ensure`/`remove` 快路径。

---

## 6. 客户端变更

- **拉 configs**：拿到节点列表 + 自己的 privkey/IP（不再每台一份配置）。
- **连接某节点前**：先 `POST /api/mobile/ensure-peer {device_id, [server_id]}`（已 provisioned 则秒返回）→ 再 startVpn。
- **打开节点列表**：后台批量 `ensure-peer` 所有列出节点。
- **启动**：预热"上次用的 + 推荐最低延迟"。
- 切节点的剩余耗时 = WG 握手本身（亚秒），不可再压。

---

## 7. 分阶段迁移（建议顺序）

| 阶段 | 内容 | 风险 |
|---|---|---|
| P1 | DB：`vpn_devices` 加 IP/密钥列 + 分配函数；回填现有设备 | 低（加列+回填） |
| P2 | 服务器：3 台子网改 `/16` + vpn-api `ensure`/`remove` | 中（重配隧道，需重连测试） |
| P3 | Portal：`device` 注册分配 IP；`configs` 改为不预建 + `ensure-peer` 接口 | 中（核心路径，灰度） |
| P4 | 客户端：connect 前 ensure + 列表预热 + 启动预热；发版 | 中（连接体验，需真机测） |
| P5 | GC cron：回收闲置 peer | 低 |

> 每阶段可独立上线 + 回滚。P1/P2 不影响现网（旧路径仍工作）；P3/P4 联动切换，建议灰度。

---

## 8. 风险与注意

- **IP 分配并发**：必须用 `FOR UPDATE SKIP LOCKED` 或序列，杜绝撞号（已有唯一索引兜底）。
- **per-device 不是 per-user**：分配粒度是设备。
- **/16 上限 ~6.5 万设备**（全局），到顶再放大 `/15`。
- **首次访问新节点有一次 ensure 往返**（~HTTPS RTT），靠"列表预热"消化；冷路径仍 < 1–2s。
- **GC 误删**：阈值给足（≥14 天未握手），且 DB 留记录可秒恢复。
- **与限速兼容**：无缝——`ratelimit-sync` 现在按 `vpn_device_peers` 返回 IP；改造后仍能按"该服务器上 provisioned 的设备"返回，且 IP 全局一致更准。

---

## 9. 决策记录

- ✅ 砍掉"UDP/Realtime 手势预判"，改用"列表打开批量预热 + 启动预热 + 闲置 GC"（等效、简单、鲁棒）。
- ✅ 限速先行（已上线），本架构改造紧随其后。
- ✅ IP 全局一致（per-device），密钥一次性生成、跨服务器复用。
- ✅ **IP 分配用方案 B**（`ip_pool` 表，可回收）。
- ✅ **GC 天数可配**（`app_config.peer_gc_days`），当前 **30 天**。
- ✅ **子网 `10.200.0.0/16`**。

## 10. 实施进度

- [ ] P1 DB 迁移 `016_ondemand_provisioning.sql`
- [ ] P2 服务器子网 /16 + vpn-api ensure/remove
- [ ] P3 Portal：configs 不预建 + ensure-peer 接口 + 注册分配 IP
- [ ] P4 客户端：connect 前 ensure + 列表/启动预热
- [ ] P5 GC cron
