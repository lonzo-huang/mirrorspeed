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
ExecStart=${VENV_DIR}/bin/uvicorn main:app --host 127.0.0.1 --port 8443
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
echo "  vpn-api 已启动，监听 127.0.0.1:8443"

# ── 在 Nginx 添加 /vpn-api/ 反代路径（幂等，已存在则跳过）──────────────────
echo "[*] 配置 Nginx /vpn-api/ 反代..."
if ! grep -q "location /vpn-api/" "${NGINX_CONF}" 2>/dev/null; then
    sed -i '/location \/secure-tunnel\//i\    # ── VPN 管理 API ──────────────────────────────────────────────────────────────────\n    location \/vpn-api\/ {\n        proxy_pass         http:\/\/127.0.0.1:8443\/;\n        proxy_http_version 1.1;\n        proxy_set_header   Host \$host;\n        proxy_set_header   X-Real-IP \$remote_addr;\n        proxy_read_timeout 30s;\n    }\n' "${NGINX_CONF}"
    nginx -t && systemctl reload nginx
    echo "  Nginx /vpn-api/ 反代已添加"
else
    echo "  Nginx /vpn-api/ 已存在，跳过"
fi

# ── 输出结果 ─────────────────────────────────────────────────────────────────
DOMAIN=$(grep -oP '(?<=server_name )[\w.-]+' "${NGINX_CONF}" 2>/dev/null | head -1 || echo "your-domain.com")
WG_PUBKEY=$(cat /etc/wireguard/server-public.key 2>/dev/null || echo "（未找到，WireGuard 未安装）")

echo ""
echo "vpn-api 部署完成："
echo "  本地健康检查: curl http://127.0.0.1:8443/health"
echo "  公网健康检查: curl https://${DOMAIN}/vpn-api/health"
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
