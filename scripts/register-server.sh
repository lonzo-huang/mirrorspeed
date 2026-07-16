#!/bin/bash
# scripts/register-server.sh — 将新 VPN 服务器注册到 Portal（Supabase + Vercel）
# 在本机（开发机，有 Vercel CLI 的环境）执行
#
# 前置条件：
#   1. 已安装 Vercel CLI 并登录（vercel whoami 有输出）
#   2. 新服务器已完成 install.sh + 07-vpnapi-setup.sh 部署
#   3. curl、openssl 可用
#
# 用法：
#   bash scripts/register-server.sh \
#     --name    JP01 \
#     --display "日本 01" \
#     --location "Tokyo" \
#     --country JP \
#     --emoji   "🇯🇵" \
#     --endpoint jp01.yourdomain.com \
#     --pubkey  "<服务端公钥>" \
#     --api-secret  "<该服务器 VPN_API_SECRET>" \
#     --port-secret "<该服务器 /etc/wireguard/.port-secret>" \
#     --awg-params  "jc,jmin,jmax,s1,s2,h1,h2,h3,h4" \
#     [--sort   2]
#
#   --awg-params 必须与服务端 /etc/wireguard/awg-params.env 完全一致。
#
#   提示：install.sh 部署完成后会在控制台直接打印好这条命令（值已填好），复制即可。
#
# API 地址自动推导为 https://<endpoint>/vpn-api
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORTAL_DIR="${PROJECT_ROOT}/portal"

# ── 颜色 ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${CYAN}▶ $*${NC}"; }

# ── 解析参数 ─────────────────────────────────────────────────────────────────
NAME="" DISPLAY_NAME="" LOCATION="" COUNTRY="" EMOJI="" ENDPOINT="" PUBKEY="" SORT=99
API_SECRET="" PORT_SECRET="" AWG_PARAMS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)        NAME="$2";         shift 2 ;;
        --display)     DISPLAY_NAME="$2"; shift 2 ;;
        --location)    LOCATION="$2";     shift 2 ;;
        --country)     COUNTRY="$2";      shift 2 ;;
        --emoji)       EMOJI="$2";        shift 2 ;;
        --endpoint)    ENDPOINT="$2";     shift 2 ;;
        --pubkey)      PUBKEY="$2";       shift 2 ;;
        --api-secret)  API_SECRET="$2";   shift 2 ;;
        --port-secret) PORT_SECRET="$2";  shift 2 ;;
        # 混淆参数，逗号分隔：jc,jmin,jmax,s1,s2,h1,h2,h3,h4
        --awg-params)  AWG_PARAMS="$2";   shift 2 ;;
        --sort)        SORT="$2";         shift 2 ;;
        *) err "未知参数: $1" ;;
    esac
done

# ── 参数校验 ─────────────────────────────────────────────────────────────────
MISSING=()
[[ -z "${NAME}"         ]] && MISSING+=(--name)
[[ -z "${DISPLAY_NAME}" ]] && MISSING+=(--display)
[[ -z "${LOCATION}"     ]] && MISSING+=(--location)
[[ -z "${COUNTRY}"      ]] && MISSING+=(--country)
[[ -z "${EMOJI}"        ]] && MISSING+=(--emoji)
[[ -z "${ENDPOINT}"     ]] && MISSING+=(--endpoint)
[[ -z "${PUBKEY}"       ]] && MISSING+=(--pubkey)

if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "缺少必填参数: ${MISSING[*]}

示例：
  bash scripts/register-server.sh \\
    --name    JP01 \\
    --display \"日本 01\" \\
    --location \"Tokyo\" \\
    --country JP \\
    --emoji   \"🇯🇵\" \\
    --endpoint jp01.yourdomain.com \\
    --pubkey  \"WireGuard公钥\" \\
    --sort    2"
fi

API_URL="https://${ENDPOINT}/vpn-api"

# api_secret / port_secret 缺失会导致 provisioning 403 / 客户端无法算端口
[[ -z "${API_SECRET}"  ]] && warn "未提供 --api-secret：节点将缺少鉴权密钥，provisioning 会 403（强烈建议提供）"
[[ -z "${PORT_SECRET}" ]] && warn "未提供 --port-secret：客户端无法计算动态端口（强烈建议提供）"

# 组装可选字段（仅在提供时写入，避免 PATCH 时把已有值清空）
EXTRA_JSON=""
[[ -n "${API_SECRET}"  ]] && EXTRA_JSON="${EXTRA_JSON}\"api_secret\": \"${API_SECRET}\","
[[ -n "${PORT_SECRET}" ]] && EXTRA_JSON="${EXTRA_JSON}\"port_secret\": \"${PORT_SECRET}\","

# 混淆参数：jc,jmin,jmax,s1,s2,h1,h2,h3,h4 —— 必须与服务端 awg0 完全一致，
# 否则客户端配置缺少混淆字段，握手会被服务端丢弃（连上但流量不通）。
if [[ -n "${AWG_PARAMS}" ]]; then
    IFS=',' read -r A_JC A_JMIN A_JMAX A_S1 A_S2 A_H1 A_H2 A_H3 A_H4 <<< "${AWG_PARAMS}"
    if [[ -z "${A_H4}" ]]; then
        err "--awg-params 需要 9 个逗号分隔的值: jc,jmin,jmax,s1,s2,h1,h2,h3,h4"
    fi
    EXTRA_JSON="${EXTRA_JSON}\"awg_jc\": ${A_JC}, \"awg_jmin\": ${A_JMIN}, \"awg_jmax\": ${A_JMAX}, \"awg_s1\": ${A_S1}, \"awg_s2\": ${A_S2}, \"awg_h1\": ${A_H1}, \"awg_h2\": ${A_H2}, \"awg_h3\": ${A_H3}, \"awg_h4\": ${A_H4},"
else
    warn "未提供 --awg-params：客户端配置将缺少混淆参数，可能连上但流量不通（强烈建议提供）"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  新服务器注册信息："
echo "    名称:        ${NAME} (${DISPLAY_NAME})"
echo "    地区:        ${LOCATION} [${COUNTRY}] ${EMOJI}"
echo "    域名:        ${ENDPOINT}"
echo "    公钥:        ${PUBKEY:0:20}..."
echo "    API:         ${API_URL}"
echo "    api_secret:  ${API_SECRET:+已提供}${API_SECRET:-（缺失）}"
echo "    port_secret: ${PORT_SECRET:+已提供}${PORT_SECRET:-（缺失）}"
echo "    awg_params:  ${AWG_PARAMS:-（缺失）}"
echo "    排序:        ${SORT}"
echo "════════════════════════════════════════════════════════"
echo ""
read -r -p "确认注册？[y/N] " CONFIRM
[[ "${CONFIRM}" =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

# ── 获取 Supabase 凭据 ────────────────────────────────────────────────────────
step "获取 Supabase 凭据..."

# 优先使用已有 .env.local；否则通过 vercel env pull 拉取
ENV_FILE="${PORTAL_DIR}/.env.local"
TEMP_ENV=false

if [[ ! -f "${ENV_FILE}" ]]; then
    info "未找到 .env.local，通过 Vercel CLI 拉取环境变量..."
    command -v vercel &>/dev/null || err "Vercel CLI 未安装，请先安装: npm i -g vercel"
    vercel env pull "${ENV_FILE}" --environment production --cwd "${PROJECT_ROOT}" --yes 2>/dev/null || \
        err "vercel env pull 失败，请确认 Vercel CLI 已登录且项目已关联"
    TEMP_ENV=true
fi

# 从 .env.local 读取凭据
SUPABASE_URL=$(grep '^NEXT_PUBLIC_SUPABASE_URL=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"' | tr -d "'")
SERVICE_KEY=$(grep '^SUPABASE_SERVICE_ROLE_KEY=' "${ENV_FILE}" | cut -d= -f2- | tr -d '"' | tr -d "'")

[[ -z "${SUPABASE_URL}" ]]  && err "未找到 NEXT_PUBLIC_SUPABASE_URL，请检查 .env.local 或 Vercel 配置"
[[ -z "${SERVICE_KEY}" ]]   && err "未找到 SUPABASE_SERVICE_ROLE_KEY，请检查 .env.local 或 Vercel 配置"

info "Supabase URL: ${SUPABASE_URL}"

# ── 健康检查：确认新服务器的 vpn-api 可达 ────────────────────────────────────
step "检查新服务器 vpn-api 是否可达..."
HEALTH_URL="${API_URL}/health"
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${HEALTH_URL}" 2>/dev/null || echo "000")

if [[ "${HTTP_CODE}" == "200" ]]; then
    info "vpn-api 健康检查通过 (HTTP 200)"
else
    warn "vpn-api 健康检查返回 HTTP ${HTTP_CODE}（${HEALTH_URL}）"
    warn "服务器可能未就绪，但仍将继续注册"
fi

# ── 检查服务器名称是否已存在 ────────────────────────────────────────────────
step "检查服务器名称是否重复..."
EXISTING=$(curl -fsSL \
    "${SUPABASE_URL}/rest/v1/vpn_servers?name=eq.${NAME}&select=id,name" \
    -H "apikey: ${SERVICE_KEY}" \
    -H "Authorization: Bearer ${SERVICE_KEY}" 2>/dev/null || echo "[]")

if [[ "${EXISTING}" != "[]" && "${EXISTING}" != "" ]]; then
    warn "服务器 ${NAME} 已存在于数据库"
    read -r -p "是否覆盖更新？[y/N] " OVERWRITE
    if [[ "${OVERWRITE}" =~ ^[Yy]$ ]]; then
        SERVER_ID=$(echo "${EXISTING}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
        info "更新现有服务器 ID: ${SERVER_ID}"
        HTTP_RESP=$(curl -s -w "\n%{http_code}" -X PATCH \
            "${SUPABASE_URL}/rest/v1/vpn_servers?id=eq.${SERVER_ID}" \
            -H "apikey: ${SERVICE_KEY}" \
            -H "Authorization: Bearer ${SERVICE_KEY}" \
            -H "Content-Type: application/json" \
            -H "Prefer: return=minimal" \
            -d "{
              ${EXTRA_JSON}
              \"display_name\": \"${DISPLAY_NAME}\",
              \"location\":     \"${LOCATION}\",
              \"country_code\": \"${COUNTRY}\",
              \"flag_emoji\":   \"${EMOJI}\",
              \"endpoint\":     \"${ENDPOINT}\",
              \"public_key\":   \"${PUBKEY}\",
              \"api_url\":      \"${API_URL}\",
              \"sort_order\":   ${SORT},
              \"is_active\":    true
            }")
        HTTP_CODE=$(echo "${HTTP_RESP}" | tail -1)
        [[ "${HTTP_CODE}" =~ ^2 ]] && info "服务器更新成功" || err "更新失败，HTTP ${HTTP_CODE}"
    else
        echo "已跳过，退出"
        exit 0
    fi
else
    # ── 插入新服务器 ────────────────────────────────────────────────────────
    step "向 Supabase 插入新服务器记录..."
    HTTP_RESP=$(curl -s -w "\n%{http_code}" -X POST \
        "${SUPABASE_URL}/rest/v1/vpn_servers" \
        -H "apikey: ${SERVICE_KEY}" \
        -H "Authorization: Bearer ${SERVICE_KEY}" \
        -H "Content-Type: application/json" \
        -H "Prefer: return=minimal" \
        -d "{
          ${EXTRA_JSON}
          \"name\":         \"${NAME}\",
          \"display_name\": \"${DISPLAY_NAME}\",
          \"location\":     \"${LOCATION}\",
          \"country_code\": \"${COUNTRY}\",
          \"flag_emoji\":   \"${EMOJI}\",
          \"endpoint\":     \"${ENDPOINT}\",
          \"port\":         51820,
          \"public_key\":   \"${PUBKEY}\",
          \"api_url\":      \"${API_URL}\",
          \"sort_order\":   ${SORT},
          \"is_active\":    true
        }")
    HTTP_CODE=$(echo "${HTTP_RESP}" | tail -1)
    [[ "${HTTP_CODE}" =~ ^2 ]] && info "服务器插入成功" || err "插入失败，HTTP ${HTTP_CODE}
响应: $(echo "${HTTP_RESP}" | head -1)"
fi

# ── 清理临时 .env.local ─────────────────────────────────────────────────────
[[ "${TEMP_ENV}" == "true" ]] && rm -f "${ENV_FILE}"

# ── 触发 Vercel 重新部署 ─────────────────────────────────────────────────────
step "触发 Vercel 重新部署..."
if command -v vercel &>/dev/null; then
    vercel deploy --prod --cwd "${PROJECT_ROOT}" --yes 2>&1 | tail -5
    info "Vercel 部署已触发"
else
    warn "未找到 vercel CLI，请手动在 Vercel Dashboard 触发重新部署"
fi

# ── 验证：触发一次 cron 同步 ─────────────────────────────────────────────────
step "等待状态同步..."

# 状态同步已从 Vercel 迁到控制机 VM01-FRA-DE（systemd timer，每 60s 一次）。
# 新节点最多 60 秒内会被自动同步进来，无需手动触发。
APP_URL=$(grep '^NEXT_PUBLIC_APP_URL=' "${ENV_FILE}" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "https://www.mirrorspeed.com")

info "新节点将在 ≤60s 内由控制机（VM01-FRA-DE）的 ms-sync-servers 自动同步"
info "想立刻同步：登录 VM01-FRA-DE 执行 systemctl start ms-sync-servers.service"
info "验证：curl -s ${APP_URL}/api/servers | python3 -m json.tool"

echo ""
echo "════════════════════════════════════════════════════════"
echo -e "  ${GREEN}✓ 服务器 ${NAME} 注册完成！${NC}"
echo ""
echo "  下一步："
echo "  1. 访问 Portal 确认节点出现在服务器列表"
echo "  2. 等待约 1 分钟，cron 自动同步服务器状态"
echo "  3. 状态变为 online 后即可用于 VPN 连接"
echo "════════════════════════════════════════════════════════"
