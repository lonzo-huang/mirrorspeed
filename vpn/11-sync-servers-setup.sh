#!/bin/bash
# 11-sync-servers-setup.sh — 节点状态同步任务（从 Vercel cron 迁到本机）
#
# 只需在【一台】服务器上装（控制机）。它会：
#   - 每 60s 并发探测所有 active 节点的 /stats /health /peers
#   - 写回 vpn_servers 状态（含「隧道死 → offline」）
#   - 同步各 peer 今日流量、对超额免费用户暂停/恢复
#
# 为什么搬：Vercel 上这个 cron 每分钟跑一次 = 1440 次/天 × 探 N 台 × 3 接口
#          + 读写 Supabase，是 Vercel 上最大的一块 CPU / 调用 / 日志开销。
#
# ⚠️ 需要 Supabase 的 service_role key（能读写整库）——只放这一台机，权限 600。
#
# 用法：
#   SUPABASE_SERVICE_KEY='<service_role key>' bash 11-sync-servers-setup.sh
#
# 前置：ms-sync-servers.py 与本脚本同目录下的 sync-servers/ 中
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/sync-servers/ms-sync-servers.py"
DST="/usr/local/bin/ms-sync-servers.py"
CONF_DIR="/etc/mirrorspeed"
CONF="${CONF_DIR}/sync-servers.env"

SUPABASE_URL="${SUPABASE_URL:-https://yqckjzfwibklwokialac.supabase.co}"
SUPABASE_SERVICE_KEY="${SUPABASE_SERVICE_KEY:-}"
SERVER_TIMEOUT="${SERVER_TIMEOUT:-8}"

# ── 参数检查 ─────────────────────────────────────────────────────────────────
if [[ -z "${SUPABASE_SERVICE_KEY}" ]]; then
    # 已装过则允许复用旧配置里的 key（便于升级脚本时无需重新传）
    if [[ -f "${CONF}" ]]; then
        SUPABASE_SERVICE_KEY="$(grep -E '^SUPABASE_SERVICE_KEY=' "${CONF}" | cut -d= -f2- | tr -d '\r"')"
    fi
fi
[[ -z "${SUPABASE_SERVICE_KEY}" ]] && {
    echo "ERROR: 缺少 SUPABASE_SERVICE_KEY"
    echo "  用法: SUPABASE_SERVICE_KEY='<service_role key>' bash $0"
    echo "  取值: Supabase → Project Settings → API → service_role secret"
    exit 1
}
[[ -f "${SRC}" ]] || { echo "ERROR: 找不到 ${SRC}"; exit 1; }

echo "[1/4] 写入配置 ${CONF}..."
mkdir -p "${CONF_DIR}"
cat > "${CONF}" <<ENVEOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
SERVER_TIMEOUT=${SERVER_TIMEOUT}
ENVEOF
chmod 600 "${CONF}"          # service_role key：仅 root 可读
echo "  已写入（权限 600，仅 root）"

echo "[2/4] 安装任务脚本 ${DST}..."
cp "${SRC}" "${DST}"
chmod 755 "${DST}"

echo "[3/4] 安装 systemd 服务 + 定时器（每 60s）..."
cat > /etc/systemd/system/ms-sync-servers.service <<'UNITEOF'
[Unit]
Description=MirrorSpeed node status / usage / quota sync
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/bin/ms-sync-servers.py
UNITEOF

cat > /etc/systemd/system/ms-sync-servers.timer <<'TIMEREOF'
[Unit]
Description=Run MirrorSpeed node sync every 60s

[Timer]
OnBootSec=45
OnUnitActiveSec=60
AccuracySec=5s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now ms-sync-servers.timer >/dev/null 2>&1 || true

echo "[4/4] 立即执行一次..."
systemctl start ms-sync-servers.service || true
sleep 2

echo ""
echo "节点同步任务部署完成："
echo "  数据源:    ${SUPABASE_URL}"
echo "  执行频率:  每 60s（systemd: ms-sync-servers.timer）"
echo ""
echo "  查看状态:  systemctl status ms-sync-servers.timer"
echo "  手动执行:  systemctl start ms-sync-servers.service"
echo "  查看日志:  journalctl -u ms-sync-servers.service -n 10 --no-pager"
echo ""
echo "  ⚠️ 确认本机日志正常后，记得去 Vercel 停掉原来的 sync-servers cron（避免两边重复跑）"
