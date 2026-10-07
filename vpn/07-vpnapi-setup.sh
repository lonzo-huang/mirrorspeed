#!/bin/bash
# 07-vpnapi-setup.sh — VPN 管理 API（FastAPI）部署
# 供 install.sh 或单独调用
#
# 前置条件：
#   - 02-nginx-setup.sh 已完成（nginx 配置文件存在）
#   - vpn-api/main.py 已上传至 ${SCRIPT_DIR}/vpn-api/main.py
#
# 环境变量：
#   VPN_API_SECRET   — API 鉴权密钥（所有服务器共用同一密钥，由 Portal Vercel 配置）
#
# 用法（单独调用）：
#   VPN_API_SECRET=xxxx bash 07-vpnapi-setup.sh
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VPNAPI_SRC="${SCRIPT_DIR}/vpn-api/main.py"
VPNAPI_DIR="/opt/mirrorspeed/vpn-api"
VENV_DIR="${VPNAPI_DIR}/venv"
NGINX_CONF="/etc/nginx/sites-available/enterprise-vpn"

# vpn-api 以【直接 TLS 监听 0.0.0.0:8443】对外(portal 直连 https://<域名>:8443，无尾斜杠)。
# 不再经 nginx /vpn-api/ 反代——nginx 以 http 反代 https 的 8443 会 502，且绑 127.0.0.1 外网不可达。
DOMAIN="${DOMAIN:-$(grep -oP '(?<=server_name )[\w.-]+' "${NGINX_CONF}" 2>/dev/null | head -1)}"
if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
    FOUND=$(ls /etc/letsencrypt/live/ 2>/dev/null | grep -E 'mirrorspeed\.com|mirrorquant\.com' | head -1)
    [[ -n "$FOUND" ]] && DOMAIN="$FOUND"
fi
CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

# ── 参数检查 ─────────────────────────────────────────────────────────────────
[[ -z "${VPN_API_SECRET:-}" ]] && {
    echo "ERROR: 请设置环境变量 VPN_API_SECRET"
    echo "  用法: VPN_API_SECRET=<密钥> bash $0"
    echo "  密钥生成: openssl rand -hex 32"
    exit 1
}
[[ -f "${VPNAPI_SRC}" ]] || {
    echo "ERROR: 找不到 ${VPNAPI_SRC}"
    echo "  请确认已将 vpn-api/ 目录上传到服务器的 ${SCRIPT_DIR}/vpn-api/"
    exit 1
}

echo "[1/5] 安装 Python 3 虚拟环境..."
apt-get install -y python3-pip python3-venv -qq

echo "[2/5] 部署 main.py..."
mkdir -p "${VPNAPI_DIR}"
cp "${VPNAPI_SRC}" "${VPNAPI_DIR}/main.py"
chmod 644 "${VPNAPI_DIR}/main.py"

echo "[3/5] 创建 venv 并安装依赖..."
python3 -m venv "${VENV_DIR}"
"${VENV_DIR}/bin/pip" install --quiet fastapi "uvicorn[standard]" python-dotenv psutil
echo "  依赖安装完成"

echo "[4/5] 写入 .env（API 鉴权密钥）..."
echo "VPN_API_SECRET=${VPN_API_SECRET}" > "${VPNAPI_DIR}/.env"
chmod 600 "${VPNAPI_DIR}/.env"

echo "[5/5] 创建 systemd 服务并启动..."
# 有证书→直接 TLS 绑 0.0.0.0(正式)；无证书→退回 http+localhost 并告警(补证书后重跑本脚本)。
if [[ -f "$CERT" && -f "$KEY" ]]; then
    UVICORN_ARGS="--host 0.0.0.0 --port 8443 --ssl-certfile ${CERT} --ssl-keyfile ${KEY}"
    LISTEN_DESC="0.0.0.0:8443 (TLS, 证书 ${DOMAIN})"
else
    echo "  WARN: 未找到 ${DOMAIN} 证书，vpn-api 暂以 http://127.0.0.1:8443 启动。"
    echo "        portal 直连 https://<域名>:8443 需要 TLS——补好证书后请重跑本脚本。"
    UVICORN_ARGS="--host 127.0.0.1 --port 8443"
    LISTEN_DESC="127.0.0.1:8443 (http, 临时)"
fi
cat > /etc/systemd/system/vpn-api.service << UNITEOF
[Unit]
Description=MirrorSpeed VPN Management API
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${VPNAPI_DIR}
EnvironmentFile=${VPNAPI_DIR}/.env
ExecStart=${VENV_DIR}/bin/uvicorn main:app ${UVICORN_ARGS}
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now vpn-api
sleep 2

systemctl is-active --quiet vpn-api || {
    echo "ERROR: vpn-api 启动失败，查看日志："
    journalctl -u vpn-api -n 30 --no-pager
    exit 1
}
echo "  vpn-api 已启动，监听 ${LISTEN_DESC}"

# 注：不再添加 nginx /vpn-api/ 反代。portal 直连 https://<域名>:8443(vpn_servers.api_url)。
# 老节点若残留该反代块无害，但 api_url 一律用 :8443 直连，勿用 /vpn-api 路径(会 502)。

# ── 输出结果 ─────────────────────────────────────────────────────────────────
WG_PUBKEY=$(cat /etc/wireguard/server-public.key 2>/dev/null || echo "（未找到，WireGuard 未安装）")

echo ""
echo "vpn-api 部署完成："
echo "  本地健康检查: curl -sk https://127.0.0.1:8443/health   (无证书临时模式用 http://)"
echo "  公网健康检查: curl https://${DOMAIN}:8443/health"
echo "  vpn_servers.api_url 应为: https://${DOMAIN}:8443  (无尾斜杠)"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "  注册到 Portal（Supabase vpn_servers 表）时需要以下信息："
echo "  endpoint:   ${DOMAIN}"
echo "  public_key: ${WG_PUBKEY}"
echo "  api_url:    https://${DOMAIN}/vpn-api"
echo "  api_secret: ${VPN_API_SECRET}"
echo ""
echo "  示例 SQL（在 Supabase SQL Editor 执行）："
echo "  INSERT INTO vpn_servers (name, display_name, location, country_code,"
echo "    flag_emoji, endpoint, port, public_key, api_url, api_secret, sort_order)"
echo "  VALUES ('SERVER_NAME', '显示名称', 'City', 'CC', '🌐',"
echo "    '${DOMAIN}', 51820, '${WG_PUBKEY}',"
echo "    'https://${DOMAIN}/vpn-api', '${VPN_API_SECRET}', 10);"
echo "╚══════════════════════════════════════════════════════════╝"
