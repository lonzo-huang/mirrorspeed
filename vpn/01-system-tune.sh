#!/bin/bash
# 01-system-tune.sh — 系统内核与网络底层调优
# 修复：补充 ip_forward（WireGuard转发必需），graceful服务禁用，缓冲区参数
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

echo "[1/4] 写入 sysctl 调优参数..."
cat > /etc/sysctl.d/99-enterprise-net.conf << 'EOF'
# ── IP 转发（WireGuard 路由必需，原框架缺失此项）──────────────────────────
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# ── BBR 拥塞控制 ──────────────────────────────────────────────────────────
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ── TCP 性能优化 ───────────────────────────────────────────────────────────
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1

# ── Socket 缓冲区（高带宽跨境链路拉满吞吐）──────────────────────────────
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

# ── 连接数与文件描述符 ────────────────────────────────────────────────────
fs.file-max = 1048576
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535

# ── 关闭冗余调试日志 ──────────────────────────────────────────────────────
net.ipv4.conf.all.log_martians = 0
net.ipv4.conf.default.log_martians = 0
EOF

# 立即生效（--system 加载所有 /etc/sysctl.d/*.conf）
sysctl --system | grep -E "(ip_forward|bbr|file-max)" | sed 's/^/  /'

echo "[2/4] 验证 CPU AES-NI 硬件加速..."
if grep -qw aes /proc/cpuinfo; then
    echo "  AES-NI 已启用，WireGuard ChaCha20 与 Nginx TLS 均可使用硬件加速"
else
    echo "  WARNING: 未检测到 AES-NI，高并发下加密性能受限"
fi

echo "[3/4] 禁用非必要服务（检查后再禁用，避免不存在的服务报错）..."
DISABLE_SVCS=(ufw apparmor rsyslog)
for svc in "${DISABLE_SVCS[@]}"; do
    if systemctl list-unit-files --quiet "${svc}.service" &>/dev/null && \
       systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
        systemctl disable --now "${svc}" && echo "  已禁用: ${svc}"
    else
        echo "  跳过（未安装或已禁用）: ${svc}"
    fi
done

echo "[4/4] 限制 journald 日志体积..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-enterprise.conf << 'EOF'
[Journal]
SystemMaxUse=100M
RuntimeMaxUse=50M
Compress=yes
EOF
systemctl restart systemd-journald

# 开启文件描述符限制（systemd 全局）
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/99-limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=65535
EOF

echo ""
echo "系统调优完成。部分参数（IP转发）已即时生效，其余建议 reboot 后全量生效。"
