# 节点安装 / 运维（唯一入口）

> 这是**节点部署的单一权威文档**。新建节点、存量节点升级、控制机、验证、踩坑都在这里。
> 设计背景（为什么迁 sing-box、三层协议）见 [singbox-migration.md](singbox-migration.md)；
> 连通性排障见 [troubleshooting-connectivity.md](troubleshooting-connectivity.md)；
> 按需发 peer 的原理见 [on-demand-provisioning.md](on-demand-provisioning.md)。

## 架构速记

- **新客户端（3.x，纯 sing-box）** 连优质节点走 sing-box 三层：
  - 快速 = **Hysteria2**（UDP 18443 + 端口跳跃）
  - 强力 = **VLESS + Reality**（TCP 443，偷大站 TLS 握手，免证书）
  - 超级 = VLESS + WS + TLS（经 Cloudflare，阶段2，暂未铺）
- **AWG 为过渡期保留**（老客户端用），双栈并存至 ~2026-12-03，之后删 AWG 及混淆。
  → AWG 相关脚本（`03-amneziawg` / `04-wstunnel` / `06-peer-manager` / `08-port-hopping` /
  `install.sh` / `reset-peers`）在该日期前**不要删**。
- 设备凭证（VLESS UUID + hy2 密码 / 或 AWG 公钥）由 portal `ensure-peer` **自动下发**，
  **不要手动加用户**。
- vpn-api 对外 **HTTPS :8443 直连**（不走 nginx 的 `/vpn-api`，否则 502）；
  `api_url = https://<域名>:8443`（**不带尾斜杠**）。

---

## 场景 A：新建干净节点（纯 sing-box，推荐；us02 就是这么装的）

适用全新主机、无旧 nginx/AWG。Reality 直接占 443，hy2 走 UDP 18443，端口跳跃 30000-49999。

```bash
cd /opt/mirrorspeed && git pull
sudo DOMAIN=<该节点域名> NODE_NAME=<大写DB name> bash vpn/04-singbox-setup.sh
# 例：DOMAIN=us02.dedione.mirrorspeed.com NODE_NAME=US02
# EMAIL 可省（默认 admin@mirrorspeed.com，仅证书到期通知）
```
脚本会：装 sing-box + certbot、签/复用证书、生成 Reality 密钥 + hy2 obfs、写配置、
nftables 端口跳跃、起服务、**[7.5/8] 自动修正并重启 vpn-api（直连 TLS :8443）**、
最后**打印现成的 UPDATE SQL**（值已填好）。

把打印的 **UPDATE** 贴进 Supabase（**只跑 UPDATE，不要跑它下面的 INSERT**——行已存在，INSERT 会多插重复）。
⚠️ **`reality_sni` 必须是纯域名**（如 `'www.microsoft.com'`）——复制时若被转成 markdown 链接
`[www.microsoft.com](...)` 要改回来，否则 Reality 握手废。

**纯 sing-box 节点必须用含本修复的 vpn-api**：早期 `/health`、`/stats` 无条件跑 `awg show`，
节点没装 awg 时会 `FileNotFoundError → 500`，导致 sync 把节点标 offline、选路里消失。
已修（缺 awg 时按 sing-box 状态上报）。装前 `git pull` 到含该修复的版本即可。

---

## 场景 B：存量 AWG 节点 → 双栈升级（老客户端零影响）

Reality 占 443 并把非 Reality 流量**回落给本机 nginx:8080**，老客户端健康探测/强力/vpn-api 照常。
hy2 端口跳跃必须避开 AWG 的 30000-49999 → 用 50000-60000。

```bash
cd /opt/mirrorspeed && git pull
NGINX_FALLBACK=1 HOP_MIN=50000 HOP_MAX=60000 \
  NODE_NAME=<大写DB name> DOMAIN=<该节点域名> bash vpn/04-singbox-setup.sh
```
同样：贴脚本打印的 **UPDATE**（不要 INSERT）。`awg_enabled` 保持 `true`（老客户端快速还要用）。

### DB `name` 大小写对照（**WHERE / NODE_NAME 必须用大写 DB name**）

| 服务端域名 | DB name |
|---|---|
| us01.dedione.mirrorspeed.com | `US01` |
| us02.dedione.mirrorspeed.com | `us02` ⚠️小写 |
| german01.tx.mirrorspeed.com | `FRA01` |
| spain01.ionos.mirrorquant.com | `ES01` |
| de02.nube.mirrorspeed.com | `DE02` |
| hk01.nube.mirrorspeed.com | `HK01` |
| jp01.ultahost.mirrorspeed.com | `JP01` |
| sg01.ultahost.mirrorspeed.com | `SG01` |

> UPDATE 确认命中（Supabase 对无 RETURNING 的 UPDATE 一律显示 “Success. No rows returned”，
> **不代表 0 行**）：
> ```sql
> SELECT name, endpoint, sb_enabled, reality_sni FROM vpn_servers WHERE name='<大写DB name>';
> ```
> 看到 `sb_enabled=true` 即成功。若 `name` 大小写/取值与 WHERE 不符才是真没命中。

---

## 场景 C：控制机（节点状态 / 用量 / 配额同步）

**只装在一台**（当前 = **FRA01 / VM01-FRA-DE**）。需要 Supabase service_role key。

```bash
cd /opt/mirrorspeed && git pull
sudo bash vpn/11-sync-servers-setup.sh   # service key 从 /etc/mirrorspeed/sync-servers.env 读
```
- 频率：节点同步每 **2min**（`ms-sync-servers.timer`）。
- 限速同步（**每台节点**各自跑一份）：`bash vpn/09-ratelimit-setup.sh`，每 **10min**。

---

## 验证清单

```bash
# 节点本机：
ss -ltnp | grep -E ':443|:18443|:8443'        # 443=sing-box, 18443=hy2, 8443=vpn-api
curl -m5 -sS -o /dev/null -w '%{http_code}\n' https://<域名>:8443/health          # 200
curl -sk -X POST https://127.0.0.1:8443/peers/ensure -H 'content-type: application/json' -d '{}'  # 401/403/422，绝不能 405/000

# 控制机(FRA01)：
journalctl -u ms-sync-servers.service -n 6 --no-pager   # 该节点不再出现在 failures
# DB：
#   SELECT name, status FROM vpn_servers WHERE name='<大写DB name>';  → online
```
最后：**新版客户端**退出重开，连该节点，快速/强力都应真正上网（连时 vpn-api 自动
`ensure-peer` + `singbox/user/ensure` 下发凭证）。

---

## 踩坑总结（排查时逐条对照）

1. **DB name 大小写 / 取值不一致**：`WHERE name='US02'` 匹配不到小写 `us02` → UPDATE 0 行 →
   `reality_pbk`/`hy2_obfs`/`sb_enabled` 全没写进去 → 新客户端连上但上不了网。**建议 WHERE 一律用
   `endpoint`**（`WHERE endpoint='us02.dedione.mirrorspeed.com'`），绕开大小写坑。
   - **Supabase 结果面板会把域名显示成 markdown 链接**（别信显示）；核实真实值用 `select length(col), col`：
     纯 `www.microsoft.com` 的 len=17。SELECT 的 "no rows" = 真 0 行（UPDATE 的 "no rows" 不是）。
   - **04 每跑一次都换 reality 密钥 + hy2 obfs** → 重跑后必须用**最后一次**打印的 SQL 重新同步
     `reality_pbk`/`hy2_obfs`，否则 pbk 对不上、obfs=null → 症状「已连接但上下行 0、反复断连」。
2. **reality_sni 被 markdown 污染**：复制 SQL 时裸域名被转成 `[www.microsoft.com](...)` → SNI 错 → Reality 废。贴纯域名。
3. **Reality 握手失败 `processed invalid connection`**：pbk/short_id/SNI 对不上。每跑一次 04 都**重新生成** reality 密钥，必须用**最后一次**的 SQL。
4. **hy2_obfs 下发成 NULL**：服务端无条件启 salamander obfs，DB 给 NULL → 快速握手被丢。脚本已输出真实 obfs 值。
5. **纯 sing-box 节点 /health、/stats 返回 500**：vpn-api 无条件跑 `awg show`，节点没 awg → FileNotFoundError。已修（缺 awg 按 sing-box 状态上报）；`git pull` + 重启 vpn-api。
6. **已连但上不了网（unknown UUID / hy2 密码不符）**：凭证没下发。两因：
   - `api_url` 走了 nginx `/vpn-api`（http 反代 https:8443 → 502）→ 改 `https://<域名>:8443` 直连；
   - vpn-api 两份 main.py 分裂（一份有 `/peers/ensure` 无 singbox）→ 已合并成一份，**git pull 后必须重启 vpn-api**（04 已自动重启 + 校验非 405）。
7. **防火墙**：存量节点 `table inet enterprise-fw`（policy drop），需放行 `tcp 8443`、`udp 18443`、`udp 50000-60000`（05-nftables 已含；手动节点确认放行）。
8. **证书**：hy2 需 TLS；脚本自动复用本机 `*.mirrorspeed.com` LE 证书。用每台**自己**的域名，别照抄示例域名。
9. **vpn-api 老配置（明文 http + 仅 127.0.0.1）→ curl 全 000**：早期 07 装的节点 `ExecStart` 是 `--host 127.0.0.1`（明文、仅本机），靠 nginx 反代；新模型要求直连 TLS、绑 0.0.0.0。04 的 [7.5/8] 已用 drop-in 自动修正。手动修：
   ```bash
   mkdir -p /etc/systemd/system/vpn-api.service.d && cat > /etc/systemd/system/vpn-api.service.d/tls.conf <<EOF
   [Service]
   ExecStart=
   ExecStart=/opt/mirrorspeed/vpn-api/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8443 --ssl-certfile /etc/letsencrypt/live/<域名>/fullchain.pem --ssl-keyfile /etc/letsencrypt/live/<域名>/privkey.pem
   EOF
   systemctl daemon-reload && systemctl restart vpn-api
   ```
10. **nginx 443 配置查找**：`sites-enabled` 多是符号链接，`grep -r` 不跟随 → 脚本 `set -e` 无声停在 [2.5/8]。已改 `grep -R` + `readlink -f`。
11. **证书续期（双栈节点）**：443=sing-box 使 webroot 自动续期失败（重定向到 443→404）；用 `certbot --standalone`（临时停 nginx）续，或见 `vpn/fix-cert.sh`。
