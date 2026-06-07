#!/bin/bash
# 03-wireguard-setup.sh — WireGuard 核心隧道 + 密钥轮换
# 修复：删除无效 LogOff 字段，自动检测 WAN 网卡，密钥文件权限，
#       key rotation heredoc 变量展开 bug，补充 PreUp IPv4转发
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_PORT=39666
WG_SUBNET="10.200.0.0/21"
WG_SERVER_IP="10.200.0.1"

echo "[1/4] 安装 WireGuard..."
apt-get update -qq
apt-get install -y wireguard-tools iptables

# 自动检测 WAN 出口网卡（修复硬编码 eth0 bug）
WAN_IF=$(ip -4 route show default | awk '{print $5; exit}')
[[ -z "${WAN_IF}" ]] && { echo "ERROR: 无法检测 WAN 网卡"; exit 1; }
echo "  检测到 WAN 网卡: ${WAN_IF}"

echo "[2/4] 生成服务端密钥对..."
mkdir -p "${WG_DIR}"
chmod 700 "${WG_DIR}"

# 私钥权限必须 600，WireGuard 会拒绝加载权限宽松的私钥
wg genkey | tee "${WG_DIR}/server-private.key" | wg pubkey > "${WG_DIR}/server-public.key"
chmod 600 "${WG_DIR}/server-private.key"
chmod 644 "${WG_DIR}/server-public.key"

SERVER_PRIVATE=$(cat "${WG_DIR}/server-private.key")
SERVER_PUBLIC=$(cat "${WG_DIR}/server-public.key")

echo "  服务端公钥: ${SERVER_PUBLIC}"

echo "[3/4] 生成 wg0.conf..."
# 修复：删除无效的 LogOff = 1 字段（WireGuard 不识别此指令）
# WAN_IF 在 PostUp/PostDown 中以实际值写入，避免 %i 仅代表 WG 接口
cat > "${WG_DIR}/${WG_IFACE}.conf" << EOF
[Interface]
Address    = ${WG_SERVER_IP}/21
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE}

# 启动时确保 IP 转发已开启（双重保险，与 sysctl 配置互补）
PreUp  = sysctl -w net.ipv4.ip_forward=1

# NAT 转发（修复：WAN 网卡名已展开为实际值，不再硬编码 eth0）
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE

# Peer 配置由 06-peer-manager.sh 追加，无需手动编辑
EOF

chmod 600 "${WG_DIR}/${WG_IFACE}.conf"

# 保存网卡名供其他脚本读取
echo "${WAN_IF}" > "${WG_DIR}/.wan-interface"

echo "[4/4] 启动 WireGuard 服务..."
systemctl enable --now "wg-quick@${WG_IFACE}"
sleep 1
wg show "${WG_IFACE}" || { echo "ERROR: WireGuard 启动失败，请检查日志: journalctl -u wg-quick@${WG_IFACE}"; exit 1; }

echo ""
echo "WireGuard 服务端部署完成："
echo "  接口: ${WG_IFACE}  地址: ${WG_SERVER_IP}/21  端口: UDP ${WG_PORT}"
echo "  公钥: ${SERVER_PUBLIC}"
echo "  请使用 06-peer-manager.sh 添加客户端"

# ── 密钥轮换脚本 ─────────────────────────────────────────────────────────
# 修复原 bug：rotation 脚本内不能用 heredoc 展开外部命令，改用独立函数写法
cat > /usr/local/bin/wg-rotate-keys.sh << 'ROTATE_SCRIPT'
#!/bin/bash
set -euo pipefail

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
BACKUP_DIR="${WG_DIR}/key-backup/$(date +%F_%H%M%S)"

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

echo "[*] 备份当前密钥与配置..."
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
cp "${WG_DIR}/server-private.key" "${WG_DIR}/server-public.key" \
   "${WG_DIR}/${WG_IFACE}.conf" "${BACKUP_DIR}/"

echo "[*] 生成新服务端密钥对..."
NEW_PRIVATE=$(wg genkey)
NEW_PUBLIC=$(echo "${NEW_PRIVATE}" | wg pubkey)

echo "${NEW_PRIVATE}" > "${WG_DIR}/server-private.key"
echo "${NEW_PUBLIC}"  > "${WG_DIR}/server-public.key"
chmod 600 "${WG_DIR}/server-private.key"

# 替换配置中的 PrivateKey 行（修复原脚本 sed 在 heredoc 单引号内无法展开变量）
sed -i "s|^PrivateKey = .*|PrivateKey = ${NEW_PRIVATE}|" "${WG_DIR}/${WG_IFACE}.conf"

echo "[*] 热重载 WireGuard（Peer 配置保留，仅更新服务端密钥）..."
# wg syncconf 比 restart 平滑：不断开已有 Peer 连接
wg syncconf "${WG_IFACE}" <(wg-quick strip "${WG_IFACE}")

echo ""
echo "密钥轮换完成。新服务端公钥: ${NEW_PUBLIC}"
echo "请通过企业安全通道将新公钥分发给所有客户端，并更新其 Peer.PublicKey 配置。"
echo "备份保存在: ${BACKUP_DIR}"
ROTATE_SCRIPT

chmod 700 /usr/local/bin/wg-rotate-keys.sh

# 安装每月自动轮换的 systemd timer（比 crontab 更可靠）
cat > /etc/systemd/system/wg-rotate-keys.service << 'EOF'
[Unit]
Description=WireGuard Server Key Rotation
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg-rotate-keys.sh
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/wg-rotate-keys.timer << 'EOF'
[Unit]
Description=Monthly WireGuard Key Rotation

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable wg-rotate-keys.timer
echo "  密钥轮换 timer 已注册（每月 1 日 00:00 自动执行）"
