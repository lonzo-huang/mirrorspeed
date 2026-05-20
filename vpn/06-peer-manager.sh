#!/bin/bash
# 06-peer-manager.sh — WireGuard 客户端 Peer 管理（新增组件）
# 用法:
#   ./06-peer-manager.sh add    <用户名>           # 添加新客户端
#   ./06-peer-manager.sh remove <用户名>           # 移除客户端
#   ./06-peer-manager.sh list                      # 列出所有 Peer
#   ./06-peer-manager.sh config <用户名>           # 显示客户端配置
#   ./06-peer-manager.sh qrcode <用户名>           # 生成二维码（需 qrencode）
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

WG_DIR="/etc/wireguard"
WG_IFACE="wg0"
WG_CONF="${WG_DIR}/${WG_IFACE}.conf"
PEERS_DIR="${WG_DIR}/peers"
SERVER_PUBLIC=$(cat "${WG_DIR}/server-public.key")
SERVER_PORT=39666

# 从服务端配置读取服务器 Address（用于确定子网）
SERVER_SUBNET=$(grep '^Address' "${WG_CONF}" | awk '{print $3}' | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3}')
# e.g. 10.200.0

DOMAIN=$(grep -oP '(?<=server_name )[\w.-]+' /etc/nginx/sites-available/enterprise-vpn 2>/dev/null | head -1)
DOMAIN="${DOMAIN:-remote.yourcompany.com}"

mkdir -p "${PEERS_DIR}"
chmod 700 "${PEERS_DIR}"

# ── 内部函数 ─────────────────────────────────────────────────────────────

# 获取当前已用的最大 IP 末位（从 .meta 文件读取，不依赖 wg show 格式）
_next_ip() {
    local max_octet=1  # 服务端占用 .1
    for meta in "${PEERS_DIR}"/*.meta; do
        [[ -f "${meta}" ]] || continue
        octet=$(grep '^ip_octet=' "${meta}" | cut -d= -f2)
        [[ -n "${octet}" ]] && (( octet > max_octet )) && max_octet=${octet}
    done
    echo $(( max_octet + 1 ))
}

_peer_exists() {
    local name="$1"
    [[ -f "${PEERS_DIR}/${name}.meta" ]]
}

# ── 子命令：add ───────────────────────────────────────────────────────────
cmd_add() {
    local name="$1"
    [[ -z "${name}" ]] && { echo "用法: $0 add <用户名>"; exit 1; }
    [[ "${name}" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "ERROR: 用户名只允许字母、数字、-、_"; exit 1; }
    _peer_exists "${name}" && { echo "ERROR: Peer '${name}' 已存在，请先 remove"; exit 1; }

    local next_octet
    next_octet=$(_next_ip)
    (( next_octet > 254 )) && { echo "ERROR: 子网 ${SERVER_SUBNET}.0/24 地址已耗尽"; exit 1; }

    local client_ip="${SERVER_SUBNET}.${next_octet}"

    echo "[*] 为 '${name}' 生成密钥对..."
    local client_private client_public preshared_key
    client_private=$(wg genkey)
    client_public=$(echo "${client_private}" | wg pubkey)
    preshared_key=$(wg genpsk)   # 预共享密钥：增加 PQ 前向安全性

    echo "[*] 写入 Peer 元数据..."
    cat > "${PEERS_DIR}/${name}.meta" << METAEOF
name=${name}
ip_octet=${next_octet}
client_ip=${client_ip}
client_public=${client_public}
added=$(date -u +%Y-%m-%dT%H:%M:%SZ)
METAEOF
    chmod 600 "${PEERS_DIR}/${name}.meta"

    # 存储客户端私钥（供 config 子命令使用，仅 root 可读）
    echo "${client_private}"  > "${PEERS_DIR}/${name}.private"
    echo "${preshared_key}"   > "${PEERS_DIR}/${name}.psk"
    chmod 600 "${PEERS_DIR}/${name}.private" "${PEERS_DIR}/${name}.psk"

    echo "[*] 追加 Peer 到 wg0.conf..."
    cat >> "${WG_CONF}" << PEEREOF

# Peer: ${name} | IP: ${client_ip} | Added: $(date -u +%Y-%m-%dT%H:%M:%SZ)
[Peer]
PublicKey    = ${client_public}
PresharedKey = ${preshared_key}
AllowedIPs   = ${client_ip}/32
PEEREOF

    echo "[*] 热加载新 Peer（不中断现有连接）..."
    wg syncconf "${WG_IFACE}" <(wg-quick strip "${WG_IFACE}")

    echo ""
    echo "Peer '${name}' 添加成功："
    echo "  VPN IP: ${client_ip}"
    echo "  公钥:   ${client_public}"
    echo ""
    echo "客户端配置文件:"
    cmd_config "${name}"
}

# ── 子命令：remove ────────────────────────────────────────────────────────
cmd_remove() {
    local name="$1"
    [[ -z "${name}" ]] && { echo "用法: $0 remove <用户名>"; exit 1; }
    _peer_exists "${name}" || { echo "ERROR: Peer '${name}' 不存在"; exit 1; }

    local pub_key
    # 用 sed 截取首个 = 之后的所有内容，保留 Base64 末尾的 = padding
    pub_key=$(grep "^client_public=" "${PEERS_DIR}/${name}.meta" | sed 's/^client_public=//')

    echo "[*] 从 wg0.conf 移除 Peer '${name}'..."
    # 删除 wg0.conf 中该 Peer 的注释行及 [Peer] 块（3行固定格式）
    # 使用 Python 确保多行删除准确，避免 sed 跨行问题
    python3 - "${WG_CONF}" "${name}" "${pub_key}" << 'PYEOF'
import sys, re

conf_path, peer_name, pub_key = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf_path, 'r') as f:
    content = f.read()

# 删除 peer 注释行 + [Peer] 块（直到下一个空白行或文件末尾）
pattern = rf'\n# Peer: {re.escape(peer_name)}.*?\n\[Peer\]\nPublicKey\s*=\s*{re.escape(pub_key)}\nPresharedKey\s*=\s*\S+\nAllowedIPs\s*=\s*\S+'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open(conf_path, 'w') as f:
    f.write(content)
print(f"  已从配置文件移除 Peer: {peer_name}")
PYEOF

    echo "[*] 从运行中接口撤销 Peer..."
    # || true：若 peer 已不在运行时接口中则忽略错误，继续清理文件
    wg set "${WG_IFACE}" peer "${pub_key}" remove || true

    echo "[*] 清理 Peer 文件..."
    rm -f "${PEERS_DIR}/${name}.meta" \
          "${PEERS_DIR}/${name}.private" \
          "${PEERS_DIR}/${name}.psk"

    echo "Peer '${name}' 已移除。"
}

# ── 子命令：list ──────────────────────────────────────────────────────────
cmd_list() {
    echo "=== 已配置的 Peers ==="
    printf "%-20s %-15s %-25s %s\n" "Name" "VPN IP" "Added" "PublicKey (prefix)"
    printf "%-20s %-15s %-25s %s\n" "----" "------" "-----" "---"

    local found=0
    for meta in "${PEERS_DIR}"/*.meta; do
        [[ -f "${meta}" ]] || continue
        found=1
        local n ip added pub
        n=$(grep '^name=' "${meta}"          | cut -d= -f2)
        ip=$(grep '^client_ip=' "${meta}"    | cut -d= -f2)
        added=$(grep '^added=' "${meta}"     | cut -d= -f2)
        pub=$(grep '^client_public=' "${meta}" | sed 's/^client_public=//')
        printf "%-20s %-15s %-25s %s...\n" "${n}" "${ip}" "${added}" "${pub:0:16}"
    done

    [[ ${found} -eq 0 ]] && echo "  (暂无 Peer，使用 '$0 add <name>' 添加)"

    echo ""
    echo "=== WireGuard 运行时状态 ==="
    wg show "${WG_IFACE}" 2>/dev/null || echo "  WireGuard 未运行"
}

# ── 子命令：config ────────────────────────────────────────────────────────
cmd_config() {
    local name="$1"
    [[ -z "${name}" ]] && { echo "用法: $0 config <用户名>"; exit 1; }
    _peer_exists "${name}" || { echo "ERROR: Peer '${name}' 不存在"; exit 1; }

    local client_private client_ip preshared_key
    client_private=$(cat "${PEERS_DIR}/${name}.private")
    preshared_key=$(cat "${PEERS_DIR}/${name}.psk")
    client_ip=$(grep '^client_ip=' "${PEERS_DIR}/${name}.meta" | cut -d= -f2)

    # 生成客户端配置（分流模式：仅企业内网走隧道）
    cat << CLIENTEOF
# ============================================================
# WireGuard 客户端配置 — ${name}
# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# 模式：分流（仅企业内网 RFC1918 走 VPN）
# ============================================================

[Interface]
PrivateKey = ${client_private}
Address    = ${client_ip}/32
DNS        = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey    = ${SERVER_PUBLIC}
PresharedKey = ${preshared_key}
Endpoint     = ${DOMAIN}:${SERVER_PORT}

# 全量公网模式：所有公网流量走 VPN，LAN（RFC1918）直连
# 等价于 0.0.0.0/0 减去 10/8、172.16/12、192.168/16，并单独放行 VPN 子网
AllowedIPs = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, 10.200.0.0/24, 2000::/3

PersistentKeepalive = 25

# ── TLS 包装模式说明（UDP 受限网络使用）────────────────────────────────
# 若直连 UDP 39666 被封锁，改用 wstunnel 包装：
# 1. 在客户端运行：
#    wstunnel client \\
#        -L "udp://127.0.0.1:39666:127.0.0.1:39666?timeout_sec=0" \\
#        wss://${DOMAIN}/secure-tunnel/
# 2. 将上方 Endpoint 改为：127.0.0.1:39666
CLIENTEOF

    # 同时写入文件
    local conf_file="${PEERS_DIR}/${name}.conf"
    cmd_config_raw "${name}" > "${conf_file}"
    chmod 600 "${conf_file}"
    echo ""
    echo "配置已保存至: ${conf_file}"
}

cmd_config_raw() {
    local name="$1"
    local client_private client_ip preshared_key
    client_private=$(cat "${PEERS_DIR}/${name}.private")
    preshared_key=$(cat "${PEERS_DIR}/${name}.psk")
    client_ip=$(grep '^client_ip=' "${PEERS_DIR}/${name}.meta" | cut -d= -f2)

    cat << RAWEOF
[Interface]
PrivateKey = ${client_private}
Address    = ${client_ip}/32
DNS        = 8.8.8.8, 1.1.1.1

[Peer]
PublicKey    = ${SERVER_PUBLIC}
PresharedKey = ${preshared_key}
Endpoint     = ${DOMAIN}:${SERVER_PORT}
AllowedIPs   = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, 10.200.0.0/24, 2000::/3
PersistentKeepalive = 25
RAWEOF
}

# ── 子命令：qrcode ────────────────────────────────────────────────────────
cmd_qrcode() {
    local name="$1"
    [[ -z "${name}" ]] && { echo "用法: $0 qrcode <用户名>"; exit 1; }
    _peer_exists "${name}" || { echo "ERROR: Peer '${name}' 不存在"; exit 1; }

    if ! command -v qrencode &>/dev/null; then
        apt-get install -y qrencode
    fi

    echo "=== ${name} 客户端二维码（手机 WireGuard App 扫码导入）==="
    cmd_config_raw "${name}" | qrencode -t UTF8
    echo ""
    echo "（二维码仅含配置，私钥已包含在内，请勿在公共场所展示）"
}

# ── 主入口 ────────────────────────────────────────────────────────────────
CMD="${1:-help}"
shift || true

case "${CMD}" in
    add)    cmd_add    "${1:-}" ;;
    remove) cmd_remove "${1:-}" ;;
    list)   cmd_list ;;
    config) cmd_config "${1:-}" ;;
    qrcode) cmd_qrcode "${1:-}" ;;
    help|--help|-h)
        echo "WireGuard Peer 管理工具"
        echo ""
        echo "用法:"
        echo "  $0 add    <用户名>   — 添加新客户端 Peer"
        echo "  $0 remove <用户名>   — 移除客户端 Peer"
        echo "  $0 list              — 列出所有 Peer 及运行状态"
        echo "  $0 config <用户名>   — 显示并保存客户端配置"
        echo "  $0 qrcode <用户名>   — 终端显示二维码（手机扫码）"
        ;;
    *)
        echo "未知命令: ${CMD}。使用 '$0 help' 查看帮助"
        exit 1
        ;;
esac
