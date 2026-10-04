# 存量节点双栈升级（一步到位）+ 本轮踩坑总结

目标：存量 AmneziaWG 节点升级成 **AWG + sing-box 双栈**，老客户端零影响、纯 sing-box 新客户端可用。
us02 是干净节点（`awg_enabled=false`），不走本流程；本文针对 `awg_enabled=true` 的存量节点。

## 术语/事实（照抄用）

- **DB `name` 区分大小写**，且与域名前缀不一致。升级脚本的 `NODE_NAME=` 与 SQL 的 `WHERE name=` 必须用下表“DB name”：

  | 服务端域名 | DB name |
  |---|---|
  | us01.dedione.mirrorspeed.com | `US01` |
  | german01.tx.mirrorspeed.com | `FRA01` |
  | spain01.ionos.mirrorquant.com | `ES01` |
  | de02.nube.mirrorspeed.com | `DE02` |
  | hk01.nube.mirrorspeed.com | `HK01` |
  | jp01.ultahost.mirrorspeed.com | `JP01` |
  | sg01.ultahost.mirrorspeed.com | `SG01` |

- sing-box 监听 **TCP 443（Reality）**，把非 Reality 流量透明回落给本机 **nginx:127.0.0.1:8080**（`NGINX_FALLBACK=1`）→ 老客户端健康探测/强力/vpn-api 照常。
- hy2 监听 **UDP 18443**，端口跳跃 **UDP 50000-60000**（避开 AWG 的 30000-49999）。
- vpn-api 对外 **HTTPS :8443**；portal 直连 `https://<域名>:8443`（**不带尾斜杠**）。
- 设备凭证（VLESS UUID + hy2 密码）由 portal `ensure-peer` 自动下发，**不要手动加用户**。

## 一步到位流程（每台节点，用它自己的域名 + 大写 DB name）

```bash
# 1. 拉最新代码(含合并版 vpn-api/main.py 与修好的 04 脚本)
cd /opt/mirrorspeed && git pull

# 2. 跑升级脚本(NGINX_FALLBACK 模式)。脚本会自动:挪 nginx→8080、Reality占443、
#    写 sing-box 配置、放行防火墙、重启 sing-box、重启 vpn-api、打印现成 SQL。
NGINX_FALLBACK=1 HOP_MIN=50000 HOP_MAX=60000 \
  NODE_NAME=<大写DBname> DOMAIN=<该节点自己的域名> bash vpn/04-singbox-setup.sh
```

脚本结尾打印的 **UPDATE SQL**（已自动填好 reality 参数、真实 obfs、`api_url=https://<域名>:8443`、
真实 api_secret）→ 贴进 Supabase SQL Editor 执行，**确认提示 “1 row affected”**（不是 "No rows returned"，
否则是 name 大小写错了）。

```bash
# 3. 验证(节点上)
ss -ltnp | grep -E ':443|:8080'                 # 443=sing-box, 8080=nginx
curl -s -o /dev/null -w '%{http_code}\n' https://<域名>:8443/health   # 期望 200,且无证书报错
curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://127.0.0.1:8443/peers/ensure \
  -H 'content-type: application/json' -d '{}'   # 期望 401/403/422,绝不能是 405
```

```bash
# 4. 客户端彻底退出重开,连该节点。盯日志应见两条 200:
journalctl -u vpn-api -f | grep -iE 'ensure'
#   POST /peers/ensure 200 且 POST /singbox/user/ensure 200
# 再确认服务端写入了真实设备用户(名字 ms-xxxx):
grep -E '"name"|"uuid"' /etc/sing-box/config.json
```

5. 老客户端刷新应仍在线；新客户端快速 + 强力都应真正上网。

## 本轮踩过的坑（逐条，排查时对照）

1. **DB name 大小写**：`WHERE name='us01'` 匹配不到 `US01` → UPDATE 0 行 → `sb_enabled` 仍 false →
   新客户端认为节点不可用、连不上。老客户端走 AWG 照常，极具迷惑性。

2. **nginx 443 配置查找**：`sites-enabled` 多是指向 `sites-available` 的符号链接，`grep -r` 不跟随 →
   脚本 `set -e` 无声退出停在 [2.5/8]。已改用 `grep -R` + `readlink -f`。

3. **Reality 握手失败 `processed invalid connection`**：客户端 Reality 参数（pbk/short_id/SNI）与服务端
   对不上。每次跑 04 都会**重新生成** reality 密钥，必须用**最后一次**跑出的 SQL，别用旧 pbk。

4. **hy2_obfs 下发成 NULL**：服务端无条件启用 salamander obfs，DB 却给 NULL → 新客户端快速缺 obfs →
   握手被丢。已改脚本输出真实 obfs 值。

5. **已连接但上不了网（unknown UUID / hy2 密码不符）**：握手过了但**认证没过**——设备凭证没被下发到服务端。
   连环两因：
   - **api_url 走了 nginx 的 `/vpn-api`**：nginx 以 `http` 反代 `https` 的 8443 → **502** → portal 的
     `/peers/ensure` 失败。改成 `api_url=https://<域名>:8443` 直连（脚本已自动输出）。
   - **vpn-api 两份 main.py 分裂**：一份有 `/peers/ensure` 无 singbox，另一份反之。存量节点 `awg_enabled=true`,
     portal 先调 AWG `/peers/ensure`，若节点跑的是缺该端点的那份 → **405** → portal `if(!resp.ok) return`
     **短路**，singbox 凭证永不下发。已合并成一份（含 `/peers/ensure`+`/peers/remove`+`/singbox/user/*`），
     **git pull 后必须重启 vpn-api**（04 脚本已自动重启 + 校验不是 405）。

6. **防火墙**：存量节点用 `table inet enterprise-fw`（policy drop），需放行 `tcp 8443`、`udp 18443`、
   `udp 50000-60000`。04 的 `ufw` 分支对 nftables 节点无效 → 确认 05-nftables 已含这些放行(已加)或手动放行。

7. **证书**：hy2 需要 TLS 证书；脚本自动复用本机已有的 `*.mirrorspeed.com` LE 证书。certbot 示例里的域名
   别照抄（曾在 US01 上误用 german01 参数导致 404）。用每台**自己**的域名。

8. **手动加的 `manualtest`/测试用户**无害，自动下发正常后可留可删。正式凭证一律由 portal 自动下发。
