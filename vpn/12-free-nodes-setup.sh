#!/bin/bash
# 12-free-nodes-setup.sh — 共享(免费机场)节点抓取器
#
# 只在【控制机】上装（和 ms-sync-servers 同一台，VM01-FRA-DE）。
# systemd timer 定时拉扫描器订阅 → 解析 → upsert 到 Supabase free_nodes。
#
# 用法：
#   SUPABASE_SERVICE_KEY='<service_role key>' \
#   FREE_NODES_SUB_URL='http://scanner.mirrorspeed.com:10611/.../subscribe2.txt' \
#   bash 12-free-nodes-setup.sh
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/free-nodes"
DST_DIR="/usr/local/lib/ms-free-nodes"
CONF_DIR="/etc/mirrorspeed"
CONF="${CONF_DIR}/free-nodes.env"

SUPABASE_URL="${SUPABASE_URL:-https://yqckjzfwibklwokialac.supabase.co}"
SUPABASE_SERVICE_KEY="${SUPABASE_SERVICE_KEY:-}"
FREE_NODES_SUB_URL="${FREE_NODES_SUB_URL:-}"
FREE_NODES_STALE_HOURS="${FREE_NODES_STALE_HOURS:-6}"
INTERVAL_SEC="${INTERVAL_SEC:-300}"          # 抓取间隔，默认 5 分钟

# 复用已有配置(升级脚本时无需重传)
if [[ -f "${CONF}" ]]; then
    [[ -z "${SUPABASE_SERVICE_KEY}" ]] && SUPABASE_SERVICE_KEY="$(grep -E '^SUPABASE_SERVICE_KEY=' "${CONF}" | cut -d= -f2- | tr -d '\r"')"
    [[ -z "${FREE_NODES_SUB_URL}"   ]] && FREE_NODES_SUB_URL="$(grep -E '^FREE_NODES_SUB_URL=' "${CONF}" | cut -d= -f2- | tr -d '\r"')"
fi
[[ -z "${SUPABASE_SERVICE_KEY}" ]] && { echo "ERROR: 缺少 SUPABASE_SERVICE_KEY"; exit 1; }
[[ -z "${FREE_NODES_SUB_URL}"   ]] && { echo "ERROR: 缺少 FREE_NODES_SUB_URL（订阅源地址）"; exit 1; }
[[ -f "${SRC_DIR}/ms-free-nodes.py" && -f "${SRC_DIR}/node_parser.py" ]] || { echo "ERROR: 找不到 ${SRC_DIR} 下的脚本"; exit 1; }

echo "[1/4] 写入配置 ${CONF}..."
mkdir -p "${CONF_DIR}"
cat > "${CONF}" <<ENVEOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_SERVICE_KEY=${SUPABASE_SERVICE_KEY}
FREE_NODES_SUB_URL=${FREE_NODES_SUB_URL}
FREE_NODES_STALE_HOURS=${FREE_NODES_STALE_HOURS}
ENVEOF
chmod 600 "${CONF}"

echo "[2/4] 安装脚本到 ${DST_DIR}..."
mkdir -p "${DST_DIR}"
cp "${SRC_DIR}/ms-free-nodes.py" "${SRC_DIR}/node_parser.py" "${DST_DIR}/"
chmod 755 "${DST_DIR}/ms-free-nodes.py"

echo "[3/4] 安装 systemd 服务 + 定时器（每 ${INTERVAL_SEC}s）..."
cat > /etc/systemd/system/ms-free-nodes.service <<UNITEOF
[Unit]
Description=MirrorSpeed free (airport) node fetcher
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${DST_DIR}/ms-free-nodes.py
UNITEOF

cat > /etc/systemd/system/ms-free-nodes.timer <<TIMEREOF
[Unit]
Description=Run MirrorSpeed free-node fetch every ${INTERVAL_SEC}s

[Timer]
OnBootSec=60
OnUnitActiveSec=${INTERVAL_SEC}
AccuracySec=10s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now ms-free-nodes.timer >/dev/null 2>&1 || true

echo "[4/4] 立即执行一次..."
systemctl start ms-free-nodes.service || true
sleep 3

echo ""
echo "共享节点抓取器部署完成："
echo "  订阅源:   ${FREE_NODES_SUB_URL}"
echo "  抓取频率: 每 ${INTERVAL_SEC}s"
echo "  日志:     journalctl -u ms-free-nodes.service -n 10 --no-pager"
