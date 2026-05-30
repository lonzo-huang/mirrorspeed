#!/bin/bash
# 03-amneziawg-setup.sh — AmneziaWG 核心隧道（WireGuard 混淆增强版）
#
# 相比标准 WireGuard 的改进：
#   - Junk-packet 混淆头：握手包插入随机填充，对抗 DPI 指纹识别
#   - 随机 magic-header（H1-H4）：覆盖 WireGuard 协议特征字节
#   - 内部固定监听 51820，由 08-port-hopping 动态映射外部端口
#
# 混淆参数存储在 /etc/wireguard/awg-params.env，peer-manager 读取后
# 写入客户端配置，服务端/客户端参数必须完全一致。
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

AWG_DIR="/etc/wireguard"                  # 密钥、参数存放目录
AWG_CONF_DIR="/etc/amnezia/amneziawg"    # awg-quick 读取 conf 的目录（Amnezia PPA 约定）
AWG_IFACE="awg0"
AWG_PORT=51820          # 内部固定端口，不直接暴露给客户端（由 port-hopping 映射）
AWG_SUBNET="10.200.0.0/24"
AWG_SERVER_IP="10.200.0.1"

# ── 安装 AmneziaWG ────────────────────────────────────────────────────────
echo "[1/5] 安装 AmneziaWG 内核模块和工具..."
OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
KERNEL_VER=$(uname -r)

apt-get update -qq
apt-get install -y --no-install-recommends \
    build-essential "linux-headers-${KERNEL_VER}" dkms \
    iptables iproute2 curl ca-certificates

if [[ "${OS_ID}" == "ubuntu" ]]; then
    echo "  检测到 Ubuntu，使用 Amnezia PPA..."
    if ! command -v add-apt-repository &>/dev/null; then
        apt-get install -y software-properties-common
    fi
    add-apt-repository -y ppa:amnezia/ppa
    apt-get update -qq
    apt-get install -y amneziawg
else
    echo "  检测到 Debian，从 GitHub Releases 下载预编译包..."
    AWG_TAG=$(curl -fsSL \
        "https://api.github.com/repos/amnezia-vpn/amneziawg-linux-kernel-module/releases/latest" \
        | grep '"tag_name"' | cut -d'"' -f4)
    [[ -z "${AWG_TAG}" ]] && { echo "ERROR: 无法获取 AmneziaWG 最新版本，检查网络"; exit 1; }
    AWG_VER="${AWG_TAG#v}"
    ARCH=$(dpkg --print-architecture)
    BASE_URL="https://github.com/amnezia-vpn/amneziawg-linux-kernel-module/releases/download/${AWG_TAG}"

    echo "  下载版本: ${AWG_TAG}  架构: ${ARCH}"
    curl -fsSL "${BASE_URL}/amneziawg-dkms_${AWG_VER}_all.deb"         -o /tmp/awg-dkms.deb
    curl -fsSL "${BASE_URL}/amneziawg-tools_${AWG_VER}_${ARCH}.deb"    -o /tmp/awg-tools.deb
    dpkg -i /tmp/awg-dkms.deb /tmp/awg-tools.deb || apt-get install -f -y
    rm -f /tmp/awg-dkms.deb /tmp/awg-tools.deb
fi

# 验证工具可用
command -v awg       || { echo "ERROR: awg 命令未找到"; exit 1; }
command -v awg-quick || { echo "ERROR: awg-quick 命令未找到"; exit 1; }

# 加载内核模块（apt 的 DKMS post-install 会 rmmod 再重建，需要在安装后重新 modprobe）
echo "  加载 amneziawg 内核模块..."
modprobe amneziawg 2>&1 || true
sleep 1
# 用 /sys/module 检查，比 lsmod | grep 更可靠
if [[ ! -d /sys/module/amneziawg ]]; then
    AWG_KO="/lib/modules/$(uname -r)/updates/dkms/amneziawg.ko"
    echo "ERROR: amneziawg 内核模块加载失败"
    echo "  当前内核: $(uname -r)"
    echo "  模块文件: $(ls -la "${AWG_KO}" 2>/dev/null || echo '不存在')"
    echo "  DKMS 状态: $(dkms status | grep amnezia || echo '无记录')"
    echo "  insmod 尝试:"
    insmod "${AWG_KO}" 2>&1 || true
    echo "  dmesg:"
    dmesg | tail -5
    exit 1
fi
echo "  amneziawg 内核模块已加载"

# ── 生成服务端密钥对 ──────────────────────────────────────────────────────
echo "[2/5] 生成服务端密钥对..."
mkdir -p "${AWG_DIR}"
chmod 700 "${AWG_DIR}"

if [[ -f "${AWG_DIR}/server-private.key" ]]; then
    echo "  密钥已存在，跳过生成（如需重置请先删除 ${AWG_DIR}/server-private.key）"
else
    awg genkey | tee "${AWG_DIR}/server-private.key" | awg pubkey > "${AWG_DIR}/server-public.key"
    chmod 600 "${AWG_DIR}/server-private.key"
    chmod 644 "${AWG_DIR}/server-public.key"
fi

SERVER_PRIVATE=$(cat "${AWG_DIR}/server-private.key")
SERVER_PUBLIC=$(cat "${AWG_DIR}/server-public.key")
echo "  服务端公钥: ${SERVER_PUBLIC}"

# ── 生成随机 AWG 混淆参数 ──────────────────────────────────────────────────
echo "[3/5] 生成随机混淆参数（Jc/Jmin/Jmax/S1/S2/H1-H4）..."

if [[ -f "${AWG_DIR}/awg-params.env" ]]; then
    echo "  混淆参数已存在，复用（如需重置请删除 ${AWG_DIR}/awg-params.env）"
    # shellcheck source=/dev/null
    source "${AWG_DIR}/awg-params.env"
else
    # Jc: junk-packet 数量（1–128，4 是较好的平衡点）
    AWG_JC=4
    # Jmin/Jmax: junk-packet 大小范围（字节）
    AWG_JMIN=40
    AWG_JMAX=70
    # S1/S2: init/response 包额外填充
    AWG_S1=0
    AWG_S2=0

    # H1-H4: 替换 WireGuard 协议特征 magic-header，必须为非零随机 uint32
    _rand_u32() {
        local val=0
        while [[ $val -eq 0 ]]; do
            val=$(od -An -tu4 -N4 /dev/urandom | tr -d ' \n')
        done
        echo "${val}"
    }

    AWG_H1=$(_rand_u32)
    AWG_H2=$(_rand_u32)
    AWG_H3=$(_rand_u32)
    AWG_H4=$(_rand_u32)

    # 持久化（peer-manager 和 vpn-api 读取此文件）
    cat > "${AWG_DIR}/awg-params.env" << PARAMSEOF
# AmneziaWG 混淆参数 — 服务端和所有客户端必须使用相同值
# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)
AWG_JC=${AWG_JC}
AWG_JMIN=${AWG_JMIN}
AWG_JMAX=${AWG_JMAX}
AWG_S1=${AWG_S1}
AWG_S2=${AWG_S2}
AWG_H1=${AWG_H1}
AWG_H2=${AWG_H2}
AWG_H3=${AWG_H3}
AWG_H4=${AWG_H4}
PARAMSEOF
    chmod 600 "${AWG_DIR}/awg-params.env"
fi

echo "  Jc=${AWG_JC}  Jmin=${AWG_JMIN}  Jmax=${AWG_JMAX}"
echo "  H1=${AWG_H1}  H2=${AWG_H2}  H3=${AWG_H3}  H4=${AWG_H4}"

# ── 自动检测 WAN 网卡 ──────────────────────────────────────────────────────
WAN_IF=$(ip -4 route ls | awk '/^default/{print $5; exit}')
[[ -z "${WAN_IF}" ]] && { echo "ERROR: 无法检测 WAN 网卡"; exit 1; }
echo "  WAN 网卡: ${WAN_IF}"
echo "${WAN_IF}" > "${AWG_DIR}/.wan-interface"

# ── 写入 awg0.conf ─────────────────────────────────────────────────────────
echo "[4/5] 生成 ${AWG_IFACE}.conf（含 AWG 混淆参数）..."
mkdir -p "${AWG_CONF_DIR}"
chmod 700 "${AWG_CONF_DIR}"

cat > "${AWG_CONF_DIR}/${AWG_IFACE}.conf" << EOF
[Interface]
Address    = ${AWG_SERVER_IP}/24
ListenPort = ${AWG_PORT}
PrivateKey = ${SERVER_PRIVATE}

# ── AmneziaWG 混淆参数（客户端配置必须完全一致）──────────────────────────
Jc   = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1   = ${AWG_S1}
S2   = ${AWG_S2}
H1   = ${AWG_H1}
H2   = ${AWG_H2}
H3   = ${AWG_H3}
H4   = ${AWG_H4}

# 确保 IP 转发已开启
PreUp  = sysctl -w net.ipv4.ip_forward=1

# NAT 转发（WAN 网卡已展开为实际值）
PostUp   = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE

# Peer 配置由 06-peer-manager.sh 追加，无需手动编辑
EOF

chmod 600 "${AWG_CONF_DIR}/${AWG_IFACE}.conf"

# ── 启动 AmneziaWG 服务 ────────────────────────────────────────────────────
echo "[5/5] 启动 AmneziaWG 服务 (awg-quick@${AWG_IFACE})..."
systemctl enable --now "awg-quick@${AWG_IFACE}"
sleep 1
awg show "${AWG_IFACE}" || {
    echo "ERROR: AmneziaWG 启动失败"
    journalctl -u "awg-quick@${AWG_IFACE}" -n 30 --no-pager
    exit 1
}

# ── 密钥轮换脚本（awg 版）────────────────────────────────────────────────
cat > /usr/local/bin/awg-rotate-keys.sh << 'ROTATE_SCRIPT'
#!/bin/bash
set -euo pipefail

AWG_DIR="/etc/wireguard"
AWG_IFACE="awg0"
BACKUP_DIR="${AWG_DIR}/key-backup/$(date +%F_%H%M%S)"

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

echo "[*] 备份当前密钥与配置..."
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
cp "${AWG_DIR}/server-private.key" "${AWG_DIR}/server-public.key" \
   "${AWG_DIR}/${AWG_IFACE}.conf"  "${BACKUP_DIR}/"

echo "[*] 生成新服务端密钥对..."
NEW_PRIVATE=$(awg genkey)
NEW_PUBLIC=$(echo "${NEW_PRIVATE}" | awg pubkey)

echo "${NEW_PRIVATE}" > "${AWG_DIR}/server-private.key"
echo "${NEW_PUBLIC}"  > "${AWG_DIR}/server-public.key"
chmod 600 "${AWG_DIR}/server-private.key"

sed -i "s|^PrivateKey = .*|PrivateKey = ${NEW_PRIVATE}|" "${AWG_DIR}/${AWG_IFACE}.conf"

echo "[*] 热重载 AmneziaWG..."
awg syncconf "${AWG_IFACE}" <(awg-quick strip "${AWG_IFACE}")

echo ""
echo "密钥轮换完成。新服务端公钥: ${NEW_PUBLIC}"
echo "备份保存在: ${BACKUP_DIR}"
ROTATE_SCRIPT

chmod 700 /usr/local/bin/awg-rotate-keys.sh

# 密钥月度轮换 timer
cat > /etc/systemd/system/awg-rotate-keys.service << 'EOF'
[Unit]
Description=AmneziaWG Server Key Rotation
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/awg-rotate-keys.sh
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/awg-rotate-keys.timer << 'EOF'
[Unit]
Description=Monthly AmneziaWG Key Rotation

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable awg-rotate-keys.timer

echo ""
echo "AmneziaWG 服务端部署完成："
echo "  接口: ${AWG_IFACE}  地址: ${AWG_SERVER_IP}/24  内部端口: UDP ${AWG_PORT}"
echo "  公钥: ${SERVER_PUBLIC}"
echo "  混淆参数: ${AWG_DIR}/awg-params.env"
echo ""
echo "  注意：客户端连接使用的是由 08-port-hopping-setup.sh 配置的动态派生端口"
echo "  请继续执行 08-port-hopping-setup.sh 完成端口跳变配置"
