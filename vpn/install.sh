#!/bin/bash
# install.sh — 主控安装编排脚本
# 按正确顺序执行各子脚本，依赖项检查，汇总部署状态
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 颜色输出 ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo ""; echo -e "${GREEN}═══ $* ═══${NC}"; echo ""; }

# ── 配置变量（环境变量预设；留空且在终端中运行时交互式询问）──────────────
# 用法 1（交互）：  bash install.sh
# 用法 2（预设）：  DOMAIN=... EMAIL=... [VPN_API_SECRET=...] bash install.sh
prompt_var() {
    # $1=变量名  $2=提示语  $3=默认值
    local cur="${!1:-}"
    [[ -n "${cur}" ]] && return
    if [[ ! -t 0 ]]; then printf -v "$1" '%s' "$3"; return; fi   # 非交互：用默认
    local input
    read -r -p "$(echo -e "${CYAN}?${NC} $2${3:+ [$3]}: ")" input
    printf -v "$1" '%s' "${input:-$3}"
}

echo ""
echo -e "${GREEN}═══ MirrorSpeed VPN 安装配置 ═══${NC}"
echo ""
prompt_var DOMAIN       "VPN 域名（已解析到本机的 A 记录）" ""
prompt_var EMAIL        "Let's Encrypt 证书通知邮箱" ""
prompt_var SRV_NAME     "节点代号（注册用，如 FRA01）" "NODE01"
prompt_var SRV_DISPLAY  "节点显示名（如 德国 法兰克福 01）" "${SRV_NAME}"
prompt_var SRV_LOCATION "节点位置（英文，如 Frankfurt）" "Unknown"
prompt_var SRV_COUNTRY  "国家代码（两位，如 DE）" "XX"
prompt_var SRV_EMOJI    "国旗 emoji（如 🇩🇪）" "🏳️"
prompt_var SRV_SORT     "列表排序（数字，越小越靠前）" "99"
FIRST_CLIENT="${FIRST_CLIENT:-employee1}"      # 初始客户端名称

[[ -z "${DOMAIN}" ]] && { err "DOMAIN 不能为空"; exit 1; }
[[ -z "${EMAIL}"  ]] && { err "EMAIL 不能为空";  exit 1; }

# vpn-api 鉴权密钥：未提供则自动生成（每台服务器独立，注册时写入 DB api_secret）
if [[ -z "${VPN_API_SECRET:-}" ]]; then
    command -v openssl &>/dev/null || { err "缺少 openssl，无法自动生成密钥"; exit 1; }
    VPN_API_SECRET="$(openssl rand -hex 32)"
    info "已自动生成 VPN_API_SECRET（注册信息会在结尾完整输出）"
fi

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
    "03-amneziawg-setup.sh"
    "04-wstunnel-setup.sh"
    "05-nftables-setup.sh"
    "08-port-hopping-setup.sh"
)

for s in "${SCRIPTS[@]}"; do
    [[ -f "${SCRIPT_DIR}/${s}" ]] || { err "缺少脚本: ${s}"; exit 1; }
    chmod +x "${SCRIPT_DIR}/${s}"
done
chmod +x "${SCRIPT_DIR}/06-peer-manager.sh"
[[ -f "${SCRIPT_DIR}/07-vpnapi-setup.sh" ]] && chmod +x "${SCRIPT_DIR}/07-vpnapi-setup.sh"
[[ -f "${SCRIPT_DIR}/08-port-hopping-setup.sh" ]] && chmod +x "${SCRIPT_DIR}/08-port-hopping-setup.sh"

# ── 开始逐步部署 ──────────────────────────────────────────────────────────

section "第 1 步：系统内核调优"
bash "${SCRIPT_DIR}/01-system-tune.sh"

section "第 2 步：Nginx TLS 前置层"
DOMAIN="${DOMAIN}" EMAIL="${EMAIL}" bash "${SCRIPT_DIR}/02-nginx-setup.sh" "${DOMAIN}" "${EMAIL}"

section "第 3 步：AmneziaWG 核心隧道（混淆增强版）"
bash "${SCRIPT_DIR}/03-amneziawg-setup.sh"

section "第 4 步：wstunnel WebSocket 封装层"
bash "${SCRIPT_DIR}/04-wstunnel-setup.sh"

section "第 5 步：nftables 防火墙策略"
bash "${SCRIPT_DIR}/05-nftables-setup.sh"

section "第 5.5 步：端口跳变（时间派生动态端口）"
bash "${SCRIPT_DIR}/08-port-hopping-setup.sh"

section "第 6 步：创建初始客户端 Peer"
bash "${SCRIPT_DIR}/06-peer-manager.sh" add "${FIRST_CLIENT}"
bash "${SCRIPT_DIR}/06-peer-manager.sh" config "${FIRST_CLIENT}"

section "第 7 步：vpn-api 管理接口"
# 注意：vpn-api/main.py 中的 wg 命令需更新为 awg（见 07-vpnapi-setup.sh 说明）
if [[ -f "${SCRIPT_DIR}/07-vpnapi-setup.sh" ]]; then
    if [[ -n "${VPN_API_SECRET}" ]]; then
        VPN_API_SECRET="${VPN_API_SECRET}" bash "${SCRIPT_DIR}/07-vpnapi-setup.sh"
    else
        warn "VPN_API_SECRET 未设置，跳过 vpn-api 部署"
        warn "如需 Portal 远程管理，请手动执行:"
        warn "  VPN_API_SECRET=<密钥> bash ${SCRIPT_DIR}/07-vpnapi-setup.sh"
        warn "部署完成后还需更新 vpn-api main.py 中的 wg 命令为 awg"
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

check "nginx 服务运行"              systemctl is-active nginx
check "AmneziaWG 接口在线"         awg show awg0
check "wstunnel 服务运行"          systemctl is-active wstunnel
check "nftables 规则已加载"        nft list ruleset
check "sysctl ip_forward=1"       bash -c '[[ $(sysctl -n net.ipv4.ip_forward) -eq 1 ]]'
check "BBR 拥塞控制已启用"         bash -c '[[ $(sysctl -n net.ipv4.tcp_congestion_control) == "bbr" ]]'
check "wstunnel 端口 2080 监听"    ss -ulnp
check "AWG UDP 51820 端口监听"     bash -c 'ss -ulnp | grep -q 51820'
check "端口跳变规则已加载"         bash -c 'iptables -t nat -L AWG_HOP | grep -q REDIRECT'
check "443 TLS 证书可访问"         bash -c "curl -fsSk --max-time 5 https://${DOMAIN}/ -o /dev/null"
[[ -n "${VPN_API_SECRET}" ]] && \
    check "vpn-api 服务运行"    systemctl is-active vpn-api

# ── 最终汇总 ──────────────────────────────────────────────────────────────
section "部署汇总"

AWG_PUBLIC=$(cat /etc/wireguard/server-public.key)
WAN_IF=$(cat /etc/wireguard/.wan-interface)

# 读取当前派生端口
AWG_CUR_PORT=""
[[ -f /etc/wireguard/.current-ports ]] && \
    AWG_CUR_PORT=$(grep '^PORT_CUR=' /etc/wireguard/.current-ports | cut -d= -f2)

# 读取 PORT_SECRET（脱敏显示）
PORT_SECRET_PREVIEW=""
[[ -f /etc/wireguard/.port-secret ]] && \
    PORT_SECRET_PREVIEW=$(cat /etc/wireguard/.port-secret | head -c 8)...

cat << SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MirrorSpeed VPN 服务端部署完成（AmneziaWG 混淆版）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  域名:           ${DOMAIN}
  WAN 网卡:       ${WAN_IF}
  服务端公钥:     ${AWG_PUBLIC}
  VPN 子网:       10.200.0.0/24

  传输层配置:
    TCP 443     — Nginx HTTPS（wstunnel WebSocket 回落）
    UDP 动态端口 — AmneziaWG 直连（每小时变化，当前: ${AWG_CUR_PORT:-未知}）
    UDP 51820   — AWG 内部端口（不对外暴露，仅 iptables DNAT 内部转发）

  各层服务:
    Nginx        $(systemctl is-active nginx)
    AmneziaWG    $(systemctl is-active awg-quick@awg0)
    wstunnel     $(systemctl is-active wstunnel)
    nftables     $(systemctl is-active nftables)
    port-rotate  $(systemctl is-active awg-port-rotate.timer 2>/dev/null || echo inactive)

  验证结果: ${PASS} 通过 / ${FAIL} 失败

  初始客户端配置:
    /etc/wireguard/peers/${FIRST_CLIENT}.conf
    （含 AWG 混淆参数，需使用 AmneziaWG 兼容客户端）

  后续操作:
    添加客户端: bash 06-peer-manager.sh add <用户名>
    移除客户端: bash 06-peer-manager.sh remove <用户名>
    查看状态:   bash 06-peer-manager.sh list
    扫码导入:   bash 06-peer-manager.sh qrcode <用户名>
    轮换密钥:   /usr/local/bin/awg-rotate-keys.sh

  注册 Portal 所需信息:
    域名:        ${DOMAIN}
    公钥:        ${AWG_PUBLIC}
    PORT_SECRET: ${PORT_SECRET_PREVIEW}（完整值见 /etc/wireguard/.port-secret）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SUMMARY

# ── 生成可直接使用的注册信息 ─────────────────────────────────────────────
PORT_SECRET_FULL=""
[[ -f /etc/wireguard/.port-secret ]] && PORT_SECRET_FULL=$(cat /etc/wireguard/.port-secret)
API_URL="https://${DOMAIN}/vpn-api"

# 读取本机的混淆参数（必须随注册写入 DB，否则 Portal 下发给客户端的配置缺少
# Jc/H1-H4，与服务端 awg0 的混淆设置不匹配 → 握手被丢弃、连上但流量不通）
AWG_JC=0 AWG_JMIN=0 AWG_JMAX=0 AWG_S1=0 AWG_S2=0 AWG_H1=0 AWG_H2=0 AWG_H3=0 AWG_H4=0
# shellcheck source=/dev/null
[[ -f /etc/wireguard/awg-params.env ]] && source /etc/wireguard/awg-params.env

cat << REGINFO

╔═══════════════════════════════════════════════════════════════╗
║  注册到 Portal —— 二选一                                        ║
╚═══════════════════════════════════════════════════════════════╝

【方式 ①】复制下面整段，到 Supabase → SQL Editor 执行：
─────────────────────────────────────────────────────────────────
INSERT INTO public.vpn_servers (
  name, display_name, location, country_code, flag_emoji,
  endpoint, port, public_key, api_url, api_secret, port_secret, sort_order, is_active,
  awg_jc, awg_jmin, awg_jmax, awg_s1, awg_s2, awg_h1, awg_h2, awg_h3, awg_h4
) VALUES (
  '${SRV_NAME}', '${SRV_DISPLAY}', '${SRV_LOCATION}', '${SRV_COUNTRY}', '${SRV_EMOJI}',
  '${DOMAIN}', 51820,
  '${AWG_PUBLIC}',
  '${API_URL}',
  '${VPN_API_SECRET}',
  '${PORT_SECRET_FULL}',
  ${SRV_SORT}, true,
  ${AWG_JC}, ${AWG_JMIN}, ${AWG_JMAX}, ${AWG_S1}, ${AWG_S2}, ${AWG_H1}, ${AWG_H2}, ${AWG_H3}, ${AWG_H4}
);
─────────────────────────────────────────────────────────────────

【方式 ②】在【开发机】（装有 Vercel CLI / 有 portal/.env.local）执行一条命令：
─────────────────────────────────────────────────────────────────
bash scripts/register-server.sh \\
  --name        '${SRV_NAME}' \\
  --display     '${SRV_DISPLAY}' \\
  --location    '${SRV_LOCATION}' \\
  --country     '${SRV_COUNTRY}' \\
  --emoji       '${SRV_EMOJI}' \\
  --endpoint    '${DOMAIN}' \\
  --pubkey      '${AWG_PUBLIC}' \\
  --api-secret  '${VPN_API_SECRET}' \\
  --port-secret '${PORT_SECRET_FULL}' \\
  --awg-params  '${AWG_JC},${AWG_JMIN},${AWG_JMAX},${AWG_S1},${AWG_S2},${AWG_H1},${AWG_H2},${AWG_H3},${AWG_H4}' \\
  --sort        ${SRV_SORT}
─────────────────────────────────────────────────────────────────

REGINFO

[[ ${FAIL} -gt 0 ]] && { err "${FAIL} 项检查失败，请查阅上方日志"; exit 1; }
