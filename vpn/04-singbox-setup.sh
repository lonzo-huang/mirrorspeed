#!/usr/bin/env bash
# 04-singbox-setup.sh — sing-box 多协议服务端(阶段1:hy2 + vless-reality)
# 适用：全新干净主机试点(如 us02.dedione.mirrorspeed.com)，不与旧 nginx/AWG 混部。
# 对应 docs/singbox-migration.md。
#
# 做了什么：
#   - 安装 sing-box + certbot
#   - certbot 签 hy2 的 TLS 证书(standalone/80)
#   - 生成 Reality 密钥对/short_id、hy2 obfs 密码、一个「测试用户」凭证
#   - 写 sing-box 服务端配置：hysteria2(UDP) + vless+reality(TCP 443)
#   - iptables 把 UDP 30000-49999 DNAT 到 hy2 固定端口(端口跳跃)
#   - 放行防火墙、起 systemd 服务
#   - 打印需要写回 Supabase vpn_servers 的参数 + 一个可直接测试的客户端信息
#
# 用法(root)：
#   sudo DOMAIN=us02.dedione.mirrorspeed.com EMAIL=admin@mirrorspeed.com bash 04-singbox-setup.sh
# 可选覆盖：REALITY_SNI(默认 www.microsoft.com) HY2_PORT(默认 18443)
#   NODE_NAME=<vpn_servers.name>  → 结尾生成的 SQL 自动填好 WHERE，直接粘贴即可
#   存量节点升级：STOP_NGINX=1 HOP_MIN=50000 HOP_MAX=60000 NODE_NAME=german01
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "请用 root 运行：sudo bash $0"; exit 1; }

DOMAIN="${DOMAIN:?必须设置 DOMAIN，如 us02.dedione.mirrorspeed.com}"
EMAIL="${EMAIL:-admin@mirrorspeed.com}"
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"   # 伪装目标(国内可达、TLS1.3、非自有大站)
REALITY_PORT=443
HY2_PORT="${HY2_PORT:-18443}"                      # hy2 固定监听 UDP 端口
# 端口跳跃范围。干净节点默认 30000-49999；存量节点(AWG 已占 30000-49999)升级时
# 必须传不重叠的范围，如 HOP_MIN=50000 HOP_MAX=60000，否则与 AWG 端口跳跃撞车。
HOP_MIN="${HOP_MIN:-30000}"; HOP_MAX="${HOP_MAX:-49999}"
SB_CONF="/etc/sing-box/config.json"

# 存量节点(nginx 占着 443)升级双栈时:停 nginx 让 Reality 占 443。
# ⚠️ 前提:必须【先】把 vpn-api 挪到独立端口(:8443 直连 TLS)并更新 DB api_url，
#    否则停 nginx 会连带断掉 /vpn-api，老客户端 AWG 发 peer 也会失败。见 docs/singbox-migration.md。
# 默认不停(干净节点无 nginx)；存量节点升级传 STOP_NGINX=1。
if [[ "${STOP_NGINX:-0}" == "1" ]] && systemctl is-active --quiet nginx; then
  echo "==> [0/8] STOP_NGINX=1:停用 nginx(释放 443 给 Reality；牺牲老客户端 wstunnel 强力)..."
  systemctl disable --now nginx || true
fi

echo "==> [1/8] 安装 sing-box + certbot ..."
apt-get update -qq
apt-get install -y curl ca-certificates nftables certbot >/dev/null
# 官方仓库装 sing-box(stable)
if ! command -v sing-box >/dev/null; then
  bash <(curl -fsSL https://sing-box.app/install.sh) || {
    echo "✗ sing-box 官方安装脚本失败，请手动安装后重跑"; exit 1; }
fi
echo "    sing-box: $(sing-box version | head -1)"

echo "==> [2/8] 签 hy2 的 TLS 证书(certbot standalone, 80)..."
# Reality 不需要证书；hy2 需要。用 standalone 占用 80 完成 http-01。
if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
  certbot certonly --standalone -d "${DOMAIN}" --email "${EMAIL}" \
    --agree-tos -n --preferred-challenges http-01
fi
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
# 证书续期后自动重启 sing-box(hy2 读的是文件)
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/restart-singbox.sh <<'HOOK'
#!/bin/bash
systemctl restart sing-box 2>/dev/null || true
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/restart-singbox.sh

echo "==> [3/8] 生成 Reality 密钥 / short_id / hy2 obfs / 测试凭证 ..."
RK=$(sing-box generate reality-keypair)
REALITY_PRIV=$(echo "$RK" | awk '/PrivateKey/{print $2}')
REALITY_PBK=$(echo "$RK"  | awk '/PublicKey/{print $2}')
REALITY_SID=$(sing-box generate rand --hex 8)
# obfs 用 hex(URL 安全,避免 /+= 在分享链接里被编码搞挂)
HY2_OBFS=$(sing-box generate rand --hex 16 2>/dev/null || openssl rand -hex 16)
# 测试用户(供你先用 sing-box/v2ray 客户端验证；正式按用户发凭证由 vpn-api 负责)
TEST_UUID=$(sing-box generate uuid)
TEST_HY2PW=$(sing-box generate rand --base64 12 2>/dev/null || openssl rand -base64 12)

echo "==> [4/8] 写 sing-box 服务端配置 ${SB_CONF} ..."
mkdir -p /etc/sing-box
cat > "${SB_CONF}" <<JSON
{
  "log": { "level": "warn", "timestamp": true },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [ { "name": "test", "password": "${TEST_HY2PW}" } ],
      "obfs": { "type": "salamander", "password": "${HY2_OBFS}" },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT}",
        "key_path": "${KEY}"
      }
    },
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [ { "name": "test", "uuid": "${TEST_UUID}" } ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_SNI}", "server_port": 443 },
          "private_key": "${REALITY_PRIV}",
          "short_id": ["${REALITY_SID}"]
        }
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
JSON
sing-box check -c "${SB_CONF}" && echo "    配置校验通过"

echo "==> [5/8] nftables：UDP ${HOP_MIN}-${HOP_MAX} 重定向到 hy2 ${HY2_PORT}(端口跳跃)..."
# 独立 table(inet ms_singbox)，不碰现有/将来的 05-nftables 主规则集。
# redirect = 本机 DNAT；客户端在 30000-49999 间跳跃，统一重定向到固定监听端口。
cat > /etc/sing-box/nftables.nft <<NFT
table inet ms_singbox {
    chain prerouting {
        type nat hook prerouting priority -100; policy accept;
        udp dport ${HOP_MIN}-${HOP_MAX} redirect to :${HY2_PORT}
    }
}
NFT
nft -f /etc/sing-box/nftables.nft
# 持久化：开机加载(不写 /etc/nftables.conf，避免与主规则集冲突)
cat > /etc/systemd/system/ms-singbox-nft.service <<'UNIT'
[Unit]
Description=MirrorSpeed sing-box nftables (hy2 port-hopping redirect)
After=network.target nftables.service
[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/sing-box/nftables.nft
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable ms-singbox-nft.service >/dev/null 2>&1 || true

echo "==> [6/8] 放行防火墙 ..."
if command -v ufw >/dev/null && ufw status | grep -q active; then
  ufw allow 80/tcp >/dev/null; ufw allow ${REALITY_PORT}/tcp >/dev/null
  ufw allow ${HOP_MIN}:${HOP_MAX}/udp >/dev/null; ufw allow ${HY2_PORT}/udp >/dev/null
fi

echo "==> [7/8] 起 systemd 服务 ..."
systemctl enable sing-box >/dev/null 2>&1 || true
systemctl restart sing-box
sleep 2
systemctl is-active --quiet sing-box && echo "    sing-box 运行中" || { echo "✗ sing-box 未起来，看 journalctl -u sing-box"; exit 1; }

# 自动读本机 vpn-api 的真实 api_secret(避免手填占位符)；NODE_NAME 为 vpn_servers.name。
API_SECRET=$(grep -m1 '^VPN_API_SECRET=' /opt/mirrorspeed/vpn-api/.env 2>/dev/null | cut -d= -f2-)
NODE_NAME="${NODE_NAME:-<填该节点在 vpn_servers 的 name>}"
API_URL="https://${DOMAIN}:8443/"
[[ -z "$API_SECRET" ]] && API_SECRET="<vpn-api 未装/未读到 .env，先装 vpn-api 再看>"

echo "==> [8/8] 完成。下面是【可直接粘贴到 Supabase SQL】的语句(值已全部填好)："
cat <<OUT

══════════ 存量节点升级 → 直接粘贴执行(未传 NODE_NAME 时改一下 WHERE 的 name) ══════════
UPDATE vpn_servers SET
  sb_enabled   = true,
  api_url      = '${API_URL}',
  api_secret   = '${API_SECRET}',
  reality_pbk  = '${REALITY_PBK}',
  reality_sid  = '${REALITY_SID}',
  reality_sni  = '${REALITY_SNI}',
  reality_port = ${REALITY_PORT},
  hy2_port     = ${HY2_PORT},
  hy2_obfs     = NULL,
  hy2_hop_min  = ${HOP_MIN},
  hy2_hop_max  = ${HOP_MAX}
WHERE name = '${NODE_NAME}';
-- awg_enabled 不动(存量节点保持 true，老客户端「快速」还要用)

══════════ 若该节点在 vpn_servers 还没有行 → 改用 INSERT(人类字段按需改) ══════════
INSERT INTO vpn_servers
  (name, display_name, country_code, flag_emoji, location, is_active, sort_order,
   endpoint, port, public_key, api_url, api_secret,
   sb_enabled, awg_enabled,
   reality_pbk, reality_sid, reality_sni, reality_port,
   hy2_port, hy2_obfs, hy2_hop_min, hy2_hop_max)
VALUES
  ('${NODE_NAME}', '改成展示名', 'US', '🇺🇸', 'Location', true, 100,
   '${DOMAIN}', 443, '', '${API_URL}', '${API_SECRET}',
   true, false,
   '${REALITY_PBK}', '${REALITY_SID}', '${REALITY_SNI}', ${REALITY_PORT},
   ${HY2_PORT}, NULL, ${HOP_MIN}, ${HOP_MAX});

── 测试用户(手动验证用；正式由 vpn-api 自动发) VLESS UUID=${TEST_UUID}  hy2 pwd=${TEST_HY2PW}
提示：以上含密钥/密码，复制到安全处，别提交进 git。
OUT
