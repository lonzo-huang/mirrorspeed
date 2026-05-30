#!/bin/bash
# 08-port-hopping-setup.sh — 时间派生端口跳变
#
# 原理：
#   客户端和服务端共享一个 PORT_SECRET，双方用相同公式独立计算
#   "当前小时"对应的 UDP 端口，每小时自动切换，无需通信协商。
#
#   port = 30000 + HMAC-SHA256(PORT_SECRET, UTC_hour_window)[0:4] % 20000
#
#   UTC_hour_window = floor(unix_timestamp / 3600)  ← 每小时变化一次
#
# 服务端实现：
#   iptables DNAT 将 "当前端口±1窗口" 全部重定向到 AWG 内部固定端口 51820
#   GFW 每小时只能封一个端口，下一小时换新端口
#
# 客户端实现（Flutter Dart，见注释末尾的参考代码）：
#   同一公式派生端口，直接连接，无需服务器告知
#
# 安全性：
#   PORT_SECRET 存储在 /etc/wireguard/.port-secret，通过 vpn-api /config
#   端点在用户首次连接时下发，之后客户端本地计算无需网络
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

AWG_DIR="/etc/wireguard"
AWG_PORT=51820                          # AWG 内部固定监听端口
PORT_SECRET_FILE="${AWG_DIR}/.port-secret"
ROTATE_BIN="/usr/local/bin/awg-port-rotate.sh"
PORT_RANGE_MIN=30000
PORT_RANGE_MAX=49999

# ── 生成或复用 PORT_SECRET ────────────────────────────────────────────────
echo "[1/4] 配置 PORT_SECRET..."

if [[ -f "${PORT_SECRET_FILE}" ]]; then
    PORT_SECRET=$(cat "${PORT_SECRET_FILE}")
    echo "  已有 PORT_SECRET，复用（如需重置请删除 ${PORT_SECRET_FILE}）"
else
    PORT_SECRET=$(openssl rand -hex 32)
    echo "${PORT_SECRET}" > "${PORT_SECRET_FILE}"
    chmod 600 "${PORT_SECRET_FILE}"
    echo "  已生成新 PORT_SECRET"
fi

echo "  PORT_SECRET: ${PORT_SECRET:0:8}...（前8位）"

# ── 安装端口轮换脚本 ──────────────────────────────────────────────────────
echo "[2/4] 安装端口轮换脚本 ${ROTATE_BIN}..."

# 确保 python3 可用（用于 HMAC-SHA256 计算）
command -v python3 || apt-get install -y python3

cat > "${ROTATE_BIN}" << 'ROTATE_EOF'
#!/bin/bash
# awg-port-rotate.sh — 计算本小时派生端口并刷新 iptables DNAT 规则
# 由 systemd timer 每小时整点触发，也可手动执行
set -euo pipefail

AWG_PORT=51820
PORT_SECRET_FILE="/etc/wireguard/.port-secret"
CHAIN="AWG_HOP"
LOG_TAG="awg-port-rotate"

[[ -f "${PORT_SECRET_FILE}" ]] || { echo "ERROR: ${PORT_SECRET_FILE} 不存在"; exit 1; }
PORT_SECRET=$(cat "${PORT_SECRET_FILE}")

# ── 端口派生函数 ─────────────────────────────────────────────────────────
# 与客户端 Dart 代码使用完全相同的算法：
#   port = 30000 + HMAC-SHA256(secret, big-endian uint64 window)[0:4] % 20000
derive_port() {
    local window=$1
    python3 - "${PORT_SECRET}" "${window}" << 'PYEOF'
import sys, hmac, hashlib, struct
secret = sys.argv[1].encode()
window = struct.pack('>Q', int(sys.argv[2]))
digest = hmac.new(secret, window, hashlib.sha256).digest()
val = struct.unpack('>I', digest[:4])[0]
print(30000 + val % 20000)
PYEOF
}

NOW=$(date -u +%s)
W_CUR=$(( NOW / 3600 ))
W_PREV=$(( W_CUR - 1 ))
W_NEXT=$(( W_CUR + 1 ))

P_PREV=$(derive_port "${W_PREV}")
P_CUR=$(derive_port "${W_CUR}")
P_NEXT=$(derive_port "${W_NEXT}")

logger -t "${LOG_TAG}" "port-hop: prev=${P_PREV} cur=${P_CUR} next=${P_NEXT} -> ${AWG_PORT} (window=${W_CUR})"
echo "[$(date -u +%H:%M:%SZ)] port-hop: prev=${P_PREV}  cur=${P_CUR}  next=${P_NEXT}  →  ${AWG_PORT}"

# ── 刷新 iptables DNAT 链 ─────────────────────────────────────────────────
# 确保自定义链存在
if ! iptables -t nat -L "${CHAIN}" &>/dev/null; then
    iptables -t nat -N "${CHAIN}"
fi

# 清空旧规则（仅清链内规则，不影响 PREROUTING）
iptables -t nat -F "${CHAIN}"

# 添加三个窗口的 DNAT 规则
for port in "${P_PREV}" "${P_CUR}" "${P_NEXT}"; do
    iptables -t nat -A "${CHAIN}" -p udp --dport "${port}" \
        -j REDIRECT --to-port "${AWG_PORT}"
done

# 确保 PREROUTING 钩入自定义链（幂等）
if ! iptables -t nat -C PREROUTING -j "${CHAIN}" 2>/dev/null; then
    iptables -t nat -I PREROUTING 1 -j "${CHAIN}"
fi

# ── 持久化当前生效端口供 vpn-api 读取 ─────────────────────────────────────
cat > /etc/wireguard/.current-ports << EOF
# 由 awg-port-rotate.sh 自动更新，勿手动修改
PORT_PREV=${P_PREV}
PORT_CUR=${P_CUR}
PORT_NEXT=${P_NEXT}
WINDOW=${W_CUR}
UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "  iptables DNAT 规则已更新"
ROTATE_EOF

chmod 755 "${ROTATE_BIN}"

# ── 安装 systemd 服务 + timer ──────────────────────────────────────────────
echo "[3/4] 安装 systemd timer（每小时整点触发）..."

cat > /etc/systemd/system/awg-port-rotate.service << EOF
[Unit]
Description=AmneziaWG Port Hop Rotation
After=network.target awg-quick@awg0.service
Requires=awg-quick@awg0.service

[Service]
Type=oneshot
ExecStart=${ROTATE_BIN}
StandardOutput=journal
StandardError=journal
EOF

# OnCalendar=hourly 在每小时 00:00 触发，与客户端时间窗口严格对齐
cat > /etc/systemd/system/awg-port-rotate.timer << 'EOF'
[Unit]
Description=AmneziaWG Hourly Port Rotation
After=awg-quick@awg0.service

[Timer]
OnCalendar=hourly
AccuracySec=5s
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable awg-port-rotate.timer

# ── 立即执行一次 ───────────────────────────────────────────────────────────
echo "[4/4] 立即应用当前小时端口规则..."
bash "${ROTATE_BIN}"

systemctl start awg-port-rotate.timer

# ── 输出汇总 ──────────────────────────────────────────────────────────────
source /etc/wireguard/.current-ports

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "  端口跳变配置完成"
echo "  AWG 内部端口：UDP ${AWG_PORT}（不对外暴露）"
echo "  当前生效端口：UDP ${PORT_CUR}（客户端此刻应使用此端口）"
echo "  ±1 窗口备用：  UDP ${PORT_PREV} / ${PORT_NEXT}"
echo "  端口范围：     30000–49999（HMAC-SHA256 派生）"
echo "  切换周期：     每小时整点 UTC（systemd timer）"
echo ""
echo "  PORT_SECRET（注册到 Portal，客户端首次下发）："
echo "  ${PORT_SECRET}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  客户端 Dart 端口派生参考代码："
echo "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
cat << 'DART_COMMENT'
  // pubspec.yaml: crypto: ^3.0.3
  import 'dart:typed_data';
  import 'package:crypto/crypto.dart';

  int deriveCurrentPort(String portSecret) {
    final hourWindow =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 3600000;
    final key = utf8.encode(portSecret);
    final msg = ByteData(8)..setUint64(0, hourWindow, Endian.big);
    final digest = Hmac(sha256, key).convert(msg.buffer.asUint8List());
    final val = ByteData.sublistView(
      Uint8List.fromList(digest.bytes), 0, 4).getUint32(0);
    return 30000 + (val % 20000);
  }
DART_COMMENT
echo "  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
