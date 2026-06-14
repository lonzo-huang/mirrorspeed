#!/bin/bash
# reset-peers.sh — 清空 awg0.conf 中所有 [Peer]（保留 [Interface]），热重载。
#
# 用途：从"全笛卡尔积"切到"按需建 peer"后，旧 peer 用的是 per-server 旧 IP，
# 会与新的全局 IP 撞车（同一 IP 两个不同密钥的 peer）→ WireGuard 把该 IP 路由给旧 peer
# → 新客户端握手成功但数据不通 → 直连失败回退中继。
# 本脚本清掉所有残留 peer；客户端（2.3.1+）重连时会自动 ensure-peer 重新干净添加。
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

CONF="/etc/amnezia/amneziawg/awg0.conf"
IFACE="awg0"
[[ -f "${CONF}" ]] || { echo "ERROR: 未找到 ${CONF}"; exit 1; }

BAK="${CONF}.bak.$(date +%s)"
cp "${CONF}" "${BAK}"
echo "已备份: ${BAK}"

before=$(grep -c '^\[Peer\]' "${CONF}" || true)

# 保留首个 peer 标记（# Name = 或 [Peer]）之前的所有内容（= [Interface] 段 + PostUp 等）
awk '
  /^# Name =/ { stop=1 }
  /^\[Peer\]/ { stop=1 }
  { if (!stop) print }
' "${BAK}" > "${CONF}"

# 热重载（不影响 [Interface]/密钥）
awg syncconf "${IFACE}" <(awg-quick strip "${IFACE}")

after=$(grep -c '^\[Peer\]' "${CONF}" || true)
echo "peer 清理完成：${before} → ${after}"
echo "客户端（2.3.1+）重新连接时会自动按需重新建 peer。"
