#!/bin/bash
# 04-wstunnel-setup.sh — WireGuard-over-WebSocket-over-TLS 封装层（新增组件）
#
# 原框架缺失此关键组件：Nginx 的 /secure-tunnel/ 路径代理到 2080 端口，
# 但 2080 端口从未有服务监听。wstunnel 填补这个缺口。
#
# 数据流：
#   客户端 AWG UDP → wstunnel client → WSS 443 → Nginx → wstunnel server:2080 → AmneziaWG server UDP 51820
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

WSTUNNEL_PORT=2080         # Nginx 反向代理目标端口（仅 127.0.0.1 监听）
WG_PORT=51820              # AmneziaWG 实际 UDP 端口（内部固定端口）
INSTALL_DIR="/usr/local/bin"
WSTUNNEL_BIN="${INSTALL_DIR}/wstunnel"

echo "[1/4] 下载 wstunnel v9.7.4..."
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64)  ARCH_TAG="amd64" ;;
    aarch64) ARCH_TAG="arm64" ;;
    *)       echo "ERROR: 不支持的架构: ${ARCH}"; exit 1 ;;
esac

# 锁定 v9.7.4：v10+ 协议完全变更（不再用 URL 路径编码目的地），
# 客户端 Dart WebSocket 只兼容 v9 的 /udp/{host}/{port} 路径格式。
LATEST_TAG="v9.7.4"
echo "  使用版本: ${LATEST_TAG}"

# 下载并验证二进制（无 GPG，校验文件大小>1MB）
DOWNLOAD_URL="https://github.com/erebe/wstunnel/releases/download/${LATEST_TAG}/wstunnel_${LATEST_TAG#v}_linux_${ARCH_TAG}.tar.gz"
TMP_DIR=$(mktemp -d)
curl -fsSL "${DOWNLOAD_URL}" -o "${TMP_DIR}/wstunnel.tar.gz"
tar -xzf "${TMP_DIR}/wstunnel.tar.gz" -C "${TMP_DIR}"
install -m 755 "${TMP_DIR}/wstunnel" "${WSTUNNEL_BIN}"
rm -rf "${TMP_DIR}"

echo "  wstunnel 安装至 ${WSTUNNEL_BIN}"
wstunnel --version 2>/dev/null || "${WSTUNNEL_BIN}" --version

echo "[2/4] 创建专用系统用户（最小权限运行）..."
id wstunnel &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin wstunnel

echo "[3/4] 创建 wstunnel 服务端 systemd 服务..."
# wstunnel server 运行在 127.0.0.1:2080（仅 Nginx 可访问，不对外暴露）
# --restrict-to 限制只能转发到本机 WireGuard UDP 端口，防止 SSRF 滥用
cat > /etc/systemd/system/wstunnel.service << UNITEOF
[Unit]
Description=wstunnel WebSocket VPN Relay
After=network.target
Wants=network.target

[Service]
Type=simple
User=wstunnel
ExecStart=${WSTUNNEL_BIN} server \\
    --restrict-to 127.0.0.1:${WG_PORT} \\
    ws://127.0.0.1:${WSTUNNEL_PORT}

# 进程安全加固
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadOnlyPaths=/
AmbientCapabilities=

Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now wstunnel

sleep 1
if systemctl is-active --quiet wstunnel; then
    echo "  wstunnel 服务运行正常，监听 127.0.0.1:${WSTUNNEL_PORT}"
else
    echo "ERROR: wstunnel 启动失败"
    journalctl -u wstunnel --no-pager -n 20
    exit 1
fi

echo "[4/4] 生成客户端 wstunnel 使用说明..."
DOMAIN=$(grep -oP '(?<=server_name )[\w.-]+' /etc/nginx/sites-available/enterprise-vpn 2>/dev/null \
    || echo "remote.yourcompany.com")

cat > /etc/wireguard/client-wstunnel-guide.txt << GUIDEOF
=== WireGuard-over-TLS 客户端配置指南 ===

架构: WireGuard UDP → wstunnel client (本地) → WSS 443 → Nginx → wstunnel server → WireGuard

【Linux / macOS 客户端配置步骤】

1. 下载 wstunnel 客户端二进制（同版本 ${LATEST_TAG}）：
   https://github.com/erebe/wstunnel/releases/tag/${LATEST_TAG}

2. 在客户端本地运行 wstunnel（将本地 UDP 39666 转发至服务器）：
   wstunnel client \\
       --connection-retry-max-backoff-sec 10 \\
       -L "udp://127.0.0.1:39666:127.0.0.1:${WG_PORT}?timeout_sec=0" \\
       wss://${DOMAIN}/secure-tunnel/

3. 修改客户端 WireGuard 配置（将 Endpoint 指向本地 wstunnel）：
   [Peer]
   Endpoint = 127.0.0.1:39666   ← 改为 wstunnel 本地监听地址
   ...（其余配置不变）

4. 启动 WireGuard：
   wg-quick up wg0

【注意】
- 若网络允许直连 UDP，直接使用 Endpoint = ${DOMAIN}:${WG_PORT} 更快
- TLS 包装模式适用于：限制 UDP 的网络环境（酒店、企业防火墙、某些国家网络）
GUIDEOF

echo ""
echo "wstunnel 部署完成："
echo "  服务端监听: ws://127.0.0.1:${WSTUNNEL_PORT}  → 转发至 WireGuard UDP ${WG_PORT}"
echo "  Nginx 入口: wss://${DOMAIN}/secure-tunnel/"
echo "  客户端指南: /etc/wireguard/client-wstunnel-guide.txt"
