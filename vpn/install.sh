#!/bin/bash
# install.sh — 主控安装编排脚本
# 按正确顺序执行各子脚本，依赖项检查，汇总部署状态
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 配置变量（部署前必须修改）────────────────────────────────────────────
DOMAIN="${DOMAIN:-remote.yourcompany.com}"     # 已解析到本服务器的域名
EMAIL="${EMAIL:-it-admin@yourcompany.com}"     # Let's Encrypt 通知邮箱
FIRST_CLIENT="${FIRST_CLIENT:-employee1}"      # 初始客户端名称
VPN_API_SECRET="${VPN_API_SECRET:-}"           # vpn-api 鉴权密钥（所有服务器共用）

# ── 颜色输出 ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo ""; echo -e "${GREEN}═══ $* ═══${NC}"; echo ""; }

# ── 前置检查 ──────────────────────────────────────────────────────────────
section "前置环境检查"

OS_ID=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
OS_VER=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
info "操作系统: ${OS_ID} ${OS_VER}"

[[ "${OS_ID}" == "ubuntu" || "${OS_ID}" == "debian" ]] || \
    { err "仅支持 Ubuntu / Debian，当前: ${OS_ID}"; exit 1; }

# 清理 cdrom apt 源（IONOS / OVH 等供应商镜像常见遗留条目，会导致 apt-get update 报错）
if grep -q '^deb.*cdrom' /etc/apt/sources.list 2>/dev/null; then
    sed -i '/^deb.*cdrom/d' /etc/apt/sources.list
    info "已移除 apt sources.list 中的 cdrom 条目"
fi

# 检查域名格式
[[ "${DOMAIN}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]] || \
    { err "DOMAIN 格式不正确: ${DOMAIN}"; exit 1; }

# 检查域名 DNS 解析
info "检查 ${DOMAIN} 是否解析至本机..."
SERVER_IP=$(curl -fsSL --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || \
            curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
DOMAIN_IP=$(dig +short "${DOMAIN}" A 2>/dev/null | tail -1 || \
            nslookup "${DOMAIN}" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1 || echo "")

if [[ -z "${SERVER_IP}" ]]; then
    warn "无法获取本机公网 IP，跳过 DNS 验证"
elif [[ "${SERVER_IP}" != "${DOMAIN_IP}" ]]; then
    warn "DNS 可能未生效: ${DOMAIN} → ${DOMAIN_IP}，本机 IP → ${SERVER_IP}"
    warn "继续安装，但 certbot 签发证书可能失败"
else
    info "DNS 解析正常: ${DOMAIN} → ${SERVER_IP}"
fi

# 检查 443/80 端口是否被占用
for port in 80 443; do
    if ss -tlnp | grep -q ":${port} "; then
        warn "端口 ${port} 已被占用，Nginx 可能启动失败"
    fi
done

# 检查必要工具
for cmd in curl ip systemctl awk; do
    command -v "${cmd}" &>/dev/null || { err "缺少命令: ${cmd}"; exit 1; }
done

info "前置检查完成"

# ── 脚本路径确认 ──────────────────────────────────────────────────────────
SCRIPTS=(
    "01-system-tune.sh"
    "02-nginx-setup.sh"
    "03-wireguard-setup.sh"
    "04-wstunnel-setup.sh"
    "05-nftables-setup.sh"
)

for s in "${SCRIPTS[@]}"; do
    [[ -f "${SCRIPT_DIR}/${s}" ]] || { err "缺少脚本: ${s}"; exit 1; }
    chmod +x "${SCRIPT_DIR}/${s}"
done
chmod +x "${SCRIPT_DIR}/06-peer-manager.sh"
[[ -f "${SCRIPT_DIR}/07-vpnapi-setup.sh" ]] && chmod +x "${SCRIPT_DIR}/07-vpnapi-setup.sh"

# ── 开始逐步部署 ──────────────────────────────────────────────────────────

section "第 1 步：系统内核调优"
bash "${SCRIPT_DIR}/01-system-tune.sh"

section "第 2 步：Nginx TLS 前置层"
DOMAIN="${DOMAIN}" EMAIL="${EMAIL}" bash "${SCRIPT_DIR}/02-nginx-setup.sh" "${DOMAIN}" "${EMAIL}"

section "第 3 步：WireGuard 核心隧道"
bash "${SCRIPT_DIR}/03-wireguard-setup.sh"

section "第 4 步：wstunnel WebSocket 封装层"
bash "${SCRIPT_DIR}/04-wstunnel-setup.sh"

section "第 5 步：nftables 防火墙策略"
bash "${SCRIPT_DIR}/05-nftables-setup.sh"

section "第 6 步：创建初始客户端 Peer"
bash "${SCRIPT_DIR}/06-peer-manager.sh" add "${FIRST_CLIENT}"
bash "${SCRIPT_DIR}/06-peer-manager.sh" config "${FIRST_CLIENT}"

section "第 7 步：vpn-api 管理接口"
if [[ -f "${SCRIPT_DIR}/07-vpnapi-setup.sh" ]]; then
    if [[ -n "${VPN_API_SECRET}" ]]; then
        VPN_API_SECRET="${VPN_API_SECRET}" bash "${SCRIPT_DIR}/07-vpnapi-setup.sh"
    else
        warn "VPN_API_SECRET 未设置，跳过 vpn-api 部署"
        warn "如需 Portal 远程管理，请手动执行:"
        warn "  VPN_API_SECRET=<密钥> bash ${SCRIPT_DIR}/07-vpnapi-setup.sh"
    fi
else
    warn "07-vpnapi-setup.sh 不存在，跳过 vpn-api 部署"
fi

# ── 部署验证 ──────────────────────────────────────────────────────────────
section "部署验证"

PASS=0; FAIL=0
check() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        info "PASS: ${label}"
        (( PASS++ )) || true
    else
        err  "FAIL: ${label}"
        (( FAIL++ )) || true
    fi
}

check "nginx 服务运行"          systemctl is-active nginx
check "wireguard 接口在线"      wg show wg0
check "wstunnel 服务运行"       systemctl is-active wstunnel
check "nftables 规则已加载"     nft list ruleset
check "sysctl ip_forward=1"    bash -c '[[ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]]'
check "BBR 拥塞控制已启用"      bash -c '[[ $(sysctl -n net.ipv4.tcp_congestion_control) == "bbr" ]]'
check "wstunnel 端口 2080 监听" ss -ulnp
check "WG UDP 39666 端口监听"   bash -c 'ss -ulnp | grep -q 39666'
check "443 TLS 证书可访问"      bash -c "curl -fsSk --max-time 5 https://${DOMAIN}/ -o /dev/null"
[[ -n "${VPN_API_SECRET}" ]] && \
    check "vpn-api 服务运行"    systemctl is-active vpn-api

# ── 最终汇总 ──────────────────────────────────────────────────────────────
section "部署汇总"

WG_PUBLIC=$(cat /etc/wireguard/server-public.key)
WAN_IF=$(cat /etc/wireguard/.wan-interface)

cat << SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  企业 VPN 服务端部署完成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  域名:         ${DOMAIN}
  WAN 网卡:     ${WAN_IF}
  服务端公钥:   ${WG_PUBLIC}
  WireGuard 子网: 10.200.0.0/24

  开放端口:
    TCP 443   — Nginx HTTPS（伪装站 + WS隧道入口）
    UDP 39666 — WireGuard 直连

  各层服务:
    Nginx     $(systemctl is-active nginx)
    WireGuard $(systemctl is-active wg-quick@wg0)
    wstunnel  $(systemctl is-active wstunnel)
    nftables  $(systemctl is-active nftables)

  验证结果: ${PASS} 通过 / ${FAIL} 失败

  初始客户端配置:
    /etc/wireguard/peers/${FIRST_CLIENT}.conf

  后续操作:
    添加客户端: bash 06-peer-manager.sh add <用户名>
    移除客户端: bash 06-peer-manager.sh remove <用户名>
    查看状态:   bash 06-peer-manager.sh list
    扫码导入:   bash 06-peer-manager.sh qrcode <用户名>
    手动轮换密钥: /usr/local/bin/wg-rotate-keys.sh

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY

[[ ${FAIL} -gt 0 ]] && { err "${FAIL} 项检查失败，请查阅上方日志"; exit 1; }
