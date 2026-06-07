#!/bin/bash
# 06-peer-manager.sh — AmneziaWG 客户端 Peer 管理
# 用法:
#   ./06-peer-manager.sh add    <用户名>           # 添加新客户端
#   ./06-peer-manager.sh remove <用户名>           # 移除客户端
#   ./06-peer-manager.sh list                      # 列出所有 Peer
#   ./06-peer-manager.sh config <用户名>           # 显示客户端配置
#   ./06-peer-manager.sh qrcode <用户名>           # 生成二维码（需 qrencode）
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

AWG_DIR="/etc/wireguard"
AWG_CONF_DIR="/etc/amnezia/amneziawg"
AWG_IFACE="awg0"
AWG_CONF="${AWG_CONF_DIR}/${AWG_IFACE}.conf"
PEERS_DIR="${AWG_DIR}/peers"
SERVER_PUBLIC=$(cat "${AWG_DIR}/server-public.key")

# 加载 AWG 混淆参数
AWG_PARAMS_FILE="${AWG_DIR}/awg-params.env"
[[ -f "${AWG_PARAMS_FILE}" ]] || { echo "ERROR: ${AWG_PARAMS_FILE} 不存在，请先执行 03-amneziawg-setup.sh"; exit 1; }
# shellcheck source=/dev/null
source "${AWG_PARAMS_FILE}"

# 加载当前派生端口
CURRENT_PORTS_FILE="${AWG_DIR}/.current-ports"
[[ -f "${CURRENT_PORTS_FILE}" ]] && source "${CURRENT_PORTS_FILE}" || PORT_CUR=""

# 服务器域名（从 nginx 配置读取）
DOMAIN=$(grep -oP '(?<=server_name )[\w.-]+' /etc/nginx/sites-available/enterprise-vpn 2>/dev/null | head -1)
DOMAIN="${DOMAIN:-remote.yourcompany.com}"

mkdir -p "${PEERS_DIR}"
chmod 700 "${PEERS_DIR}"

# ── 内部函数 ─────────────────────────────────────────────────────────────

# 返回下一个可用的主机索引（2 起，1 留给服务端）。索引跨整个子网线性增长：
# /21 子网(10.200.0.0/21) 可用索引 2..2046 → 10.200.0.2 .. 10.200.7.254。
# meta 仍用 ip_octet 字段存该索引（兼容旧 /24 数据：旧值 2..254 映射不变）。
_next_ip() {
    local max_idx=1  # 服务端占用索引 1（.1）
    for meta in "${PEERS_DIR}"/*.meta; do
        [[ -f "${meta}" ]] || continue
        octet=$(grep '^ip_octet=' "${meta}" | cut -d= -f2)
        [[ -n "${octet}" ]] && (( octet > max_idx )) && max_idx=${octet}
    done
    echo $(( max_idx + 1 ))
}

# 子网最大可用主机索引：由 Address 的前缀长度推导。/21→2046，/24→254。
_max_index() {
    local prefix
    prefix=$(grep '^Address' "${AWG_CONF}" | awk '{print $3}' | cut -d'/' -f2)
    [[ -z "${prefix}" ]] && prefix=24
    # 主机数 = 2^(32-prefix) - 2（去网络位/广播位），再减 1（服务端占 .1 之上的网络起始）
    echo $(( (1 << (32 - prefix)) - 2 ))
}

# 把线性主机索引换算成实际 IP（基于子网起始 a.b.base3.0）。
_index_to_ip() {
    local idx="$1" server_ip a b c prefix base3 oct3 oct4
    server_ip=$(grep '^Address' "${AWG_CONF}" | awk '{print $3}' | cut -d'/' -f1)
    prefix=$(grep '^Address' "${AWG_CONF}" | awk '{print $3}' | cut -d'/' -f2)
    IFS=. read -r a b c _ <<< "${server_ip}"
    # 子网内第三段对齐到块起始（/21 → 清掉低 3 位；/24 → 不变）
    local hostbits=$(( 32 - prefix ))
    if (( hostbits >= 8 )); then
        local thirdmask=$(( (0xFF << (hostbits - 8)) & 0xFF ))
        base3=$(( c & thirdmask ))
    else
        base3=${c}
    fi
    oct3=$(( base3 + idx / 256 ))
    oct4=$(( idx % 256 ))
    echo "${a}.${b}.${oct3}.${oct4}"
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
    (( next_octet > $(_max_index) )) && { echo "ERROR: 子网地址已耗尽"; exit 1; }

    local client_ip
    client_ip=$(_index_to_ip "${next_octet}")

    echo "[*] 为 '${name}' 生成 AmneziaWG 密钥对..."
    local client_private client_public preshared_key
    client_private=$(awg genkey)
    client_public=$(echo "${client_private}" | awg pubkey)
    preshared_key=$(awg genpsk)

    echo "[*] 写入 Peer 元数据..."
    cat > "${PEERS_DIR}/${name}.meta" << METAEOF
name=${name}
ip_octet=${next_octet}
client_ip=${client_ip}
client_public=${client_public}
added=$(date -u +%Y-%m-%dT%H:%M:%SZ)
METAEOF
    chmod 600 "${PEERS_DIR}/${name}.meta"

    echo "${client_private}" > "${PEERS_DIR}/${name}.private"
    echo "${preshared_key}"  > "${PEERS_DIR}/${name}.psk"
    chmod 600 "${PEERS_DIR}/${name}.private" "${PEERS_DIR}/${name}.psk"

    echo "[*] 追加 Peer 到 ${AWG_IFACE}.conf..."
    cat >> "${AWG_CONF}" << PEEREOF

# Peer: ${name} | IP: ${client_ip} | Added: $(date -u +%Y-%m-%dT%H:%M:%SZ)
[Peer]
PublicKey    = ${client_public}
PresharedKey = ${preshared_key}
AllowedIPs   = ${client_ip}/32
PEEREOF

    echo "[*] 热加载新 Peer..."
    awg syncconf "${AWG_IFACE}" <(awg-quick strip "${AWG_IFACE}")

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
    pub_key=$(grep "^client_public=" "${PEERS_DIR}/${name}.meta" | sed 's/^client_public=//')

    echo "[*] 从 ${AWG_IFACE}.conf 移除 Peer '${name}'..."
    python3 - "${AWG_CONF}" "${name}" "${pub_key}" << 'PYEOF'
import sys, re

conf_path, peer_name, pub_key = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf_path, 'r') as f:
    content = f.read()

pattern = rf'\n# Peer: {re.escape(peer_name)}.*?\n\[Peer\]\nPublicKey\s*=\s*{re.escape(pub_key)}\nPresharedKey\s*=\s*\S+\nAllowedIPs\s*=\s*\S+'
content = re.sub(pattern, '', content, flags=re.DOTALL)

with open(conf_path, 'w') as f:
    f.write(content)
print(f"  已从配置文件移除 Peer: {peer_name}")
PYEOF

    echo "[*] 从运行中接口撤销 Peer..."
    awg set "${AWG_IFACE}" peer "${pub_key}" remove || true

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
    echo "=== AmneziaWG 运行时状态 ==="
    awg show "${AWG_IFACE}" 2>/dev/null || echo "  AmneziaWG 未运行"

    echo ""
    echo "=== 当前端口跳变状态 ==="
    if [[ -f "${AWG_DIR}/.current-ports" ]]; then
        cat "${AWG_DIR}/.current-ports"
    else
        echo "  端口跳变未配置（请执行 08-port-hopping-setup.sh）"
    fi
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

    # 端点端口：优先使用当前派生端口，未配置则提示
    local endpoint_port="${PORT_CUR:-<运行08-port-hopping-setup.sh后填写>}"

    cat << CLIENTEOF
# ============================================================
# AmneziaWG 客户端配置 — ${name}
# 生成时间: $(date -u +%Y-%m-%dT%H:%M:%SZ)
#
# 端口说明：
#   Endpoint 中的端口每小时自动变化（UTC 整点）。
#   客户端 App 内置相同的派生公式，连接前自动计算当前端口，
#   无需手动更新此配置文件。
# ============================================================

[Interface]
PrivateKey = ${client_private}
Address    = ${client_ip}/32
DNS        = 8.8.8.8, 1.1.1.1

# ── AmneziaWG 混淆参数（必须与服务端完全一致）────────────────────────────
Jc   = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1   = ${AWG_S1}
S2   = ${AWG_S2}
H1   = ${AWG_H1}
H2   = ${AWG_H2}
H3   = ${AWG_H3}
H4   = ${AWG_H4}

[Peer]
PublicKey    = ${SERVER_PUBLIC}
PresharedKey = ${preshared_key}
# 端口每小时变化，客户端 App 自动计算（此处为生成时刻的当前端口）
Endpoint     = ${DOMAIN}:${endpoint_port}

# 全量公网模式（LAN RFC1918 直连，其余走 VPN）
AllowedIPs = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, 10.200.0.0/21, 2000::/3

PersistentKeepalive = 25

# ── WebSocket 回落说明（UDP 被封时使用）──────────────────────────────────
# 若动态 UDP 端口全部被封，改用 wstunnel 包装走 TCP 443：
# 1. 在客户端运行：
#    wstunnel client \\
#        -L "udp://127.0.0.1:51820:127.0.0.1:51820?timeout_sec=0" \\
#        wss://${DOMAIN}/secure-tunnel/
# 2. 将上方 Endpoint 改为：127.0.0.1:51820
CLIENTEOF

    # 同时写入文件
    local conf_file="${PEERS_DIR}/${name}.conf"
    _config_raw "${name}" > "${conf_file}"
    chmod 600 "${conf_file}"
    echo ""
    echo "配置已保存至: ${conf_file}"
}

_config_raw() {
    local name="$1"
    local client_private client_ip preshared_key
    client_private=$(cat "${PEERS_DIR}/${name}.private")
    preshared_key=$(cat "${PEERS_DIR}/${name}.psk")
    client_ip=$(grep '^client_ip=' "${PEERS_DIR}/${name}.meta" | cut -d= -f2)
    local endpoint_port="${PORT_CUR:-0}"

    cat << RAWEOF
[Interface]
PrivateKey = ${client_private}
Address    = ${client_ip}/32
DNS        = 8.8.8.8, 1.1.1.1
Jc   = ${AWG_JC}
Jmin = ${AWG_JMIN}
Jmax = ${AWG_JMAX}
S1   = ${AWG_S1}
S2   = ${AWG_S2}
H1   = ${AWG_H1}
H2   = ${AWG_H2}
H3   = ${AWG_H3}
H4   = ${AWG_H4}

[Peer]
PublicKey    = ${SERVER_PUBLIC}
PresharedKey = ${preshared_key}
Endpoint     = ${DOMAIN}:${endpoint_port}
AllowedIPs   = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, 10.200.0.0/21, 2000::/3
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

    echo "=== ${name} 客户端二维码（AmneziaWG App 扫码导入）==="
    _config_raw "${name}" | qrencode -t UTF8
    echo ""
    echo "（需使用支持 AmneziaWG 的客户端 App，标准 WireGuard App 不兼容）"
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
        echo "AmneziaWG Peer 管理工具"
        echo ""
        echo "用法:"
        echo "  $0 add    <用户名>   — 添加新客户端 Peer"
        echo "  $0 remove <用户名>   — 移除客户端 Peer"
        echo "  $0 list              — 列出所有 Peer 及运行状态"
        echo "  $0 config <用户名>   — 显示并保存客户端配置（含 AWG 混淆参数）"
        echo "  $0 qrcode <用户名>   — 终端显示二维码（AmneziaWG App 扫码）"
        ;;
    *)
        echo "未知命令: ${CMD}。使用 '$0 help' 查看帮助"
        exit 1
        ;;
esac
