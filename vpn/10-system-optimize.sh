#!/bin/bash
#===============================================================================
# 10-system-optimize.sh — VPN 网关系统精简与性能优化（可选步骤）
#
# 不在 install.sh 中自动执行：本脚本会禁用一批系统服务并卸载冗余软件包，
# 属于有副作用的操作。请在装机完成、确认隧道正常后，手动执行一次：
#     sudo bash vpn/10-system-optimize.sh
#
# 特性：自动备份 + 生成回滚脚本、幂等、虚拟机检测、BBR/缓冲区/conntrack 调优。
# 兼容：Ubuntu 22.04/24.04 | Debian 12 | 单核/多核 | 物理机/虚拟机
# 适配：AmneziaWG（awg-quick@awg0 / awg）+ vpn-api + wstunnel
#===============================================================================

set -euo pipefail

# ==================== 全局配置 ====================
LOG_FILE="/opt/mirrorspeed/env-opt.log"
BACKUP_DIR="/opt/mirrorspeed/backups/$(date +%F_%H%M%S)"
WAN_INTERFACE=$(ip -o link show 2>/dev/null | awk -F': ' '/state UP/ {print $2}' | grep -v lo | head -1)
CPU_COUNT=$(nproc 2>/dev/null || echo 1)

info_print() { echo -e "$1" | tee -a "${LOG_FILE}"; }
info_sep() {
    echo -e "\n================================================================" | tee -a "${LOG_FILE}"
    echo "$1" | tee -a "${LOG_FILE}"
    echo "================================================================" | tee -a "${LOG_FILE}"
}

safe_disable() {
    for svc in "$@"; do
        if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q . || systemctl list-unit-files "${svc}" 2>/dev/null | grep -q .; then
            systemctl disable --now "${svc}" 2>/dev/null && \
                info_print "✅ 已禁用: ${svc}" || \
                info_print "⚠️  ${svc} 禁用跳过（无权限或依赖冲突）"
        else
            info_print "ℹ️  ${svc} 未安装，跳过"
        fi
    done
}

backup_config() {
    mkdir -p "${BACKUP_DIR}"
    info_print "📦 正在备份关键配置至: ${BACKUP_DIR}"
    [ -f /etc/sysctl.d/99-vpn-tune.conf ] && cp /etc/sysctl.d/99-vpn-tune.conf "${BACKUP_DIR}/" 2>/dev/null || true
    [ -f /etc/systemd/journald.conf ] && cp /etc/systemd/journald.conf "${BACKUP_DIR}/" 2>/dev/null || true
    [ -f /etc/default/irqbalance ] && cp /etc/default/irqbalance "${BACKUP_DIR}/" 2>/dev/null || true
    systemctl list-unit-files --type=service --state=enabled > "${BACKUP_DIR}/enabled-services.txt" 2>/dev/null || true

    cat > "${BACKUP_DIR}/rollback.sh" << 'ROLLBACK'
#!/bin/bash
set -euo pipefail
BACKUP_SRC="$(dirname "$0")"
echo "[*] 正在回滚系统配置..."
[ -f "${BACKUP_SRC}/99-vpn-tune.conf" ] && { cp "${BACKUP_SRC}/99-vpn-tune.conf" /etc/sysctl.d/; sysctl -p /etc/sysctl.d/99-vpn-tune.conf 2>/dev/null || true; } || rm -f /etc/sysctl.d/99-vpn-tune.conf
[ -f "${BACKUP_SRC}/journald.conf" ] && { cp "${BACKUP_SRC}/journald.conf" /etc/systemd/; systemctl restart systemd-journald; }
[ -f "${BACKUP_SRC}/irqbalance" ] && cp "${BACKUP_SRC}/irqbalance" /etc/default/
if [ -f "${BACKUP_SRC}/enabled-services.txt" ]; then
    while IFS= read -r svc; do systemctl enable "${svc}" 2>/dev/null || true; done < "${BACKUP_SRC}/enabled-services.txt"
fi
echo "[✅] 回滚完成！建议执行: reboot"
ROLLBACK
    chmod +x "${BACKUP_DIR}/rollback.sh"
    info_print "🔄 回滚脚本已生成: ${BACKUP_DIR}/rollback.sh"
}

main() {
    [ "${EUID}" -ne 0 ] && { echo "❌ 请使用 root 权限执行: sudo bash $0"; exit 1; }
    mkdir -p "$(dirname "${LOG_FILE}")"
    > "${LOG_FILE}"
    info_sep "🚀 VPN 网关系统优化启动 [$(date '+%F %T')]"
    info_print "📋 检测到网卡: ${WAN_INTERFACE:-未知} | CPU 核心数: ${CPU_COUNT}"

    # 虚拟机检测（决定是否卸载 Guest Agent）
    IS_VM=0
    if systemd-detect-virt -q; then IS_VM=1; fi

    backup_config

    # 1. 优化前快照
    info_sep "【优化前系统状态快照】"
    {
        echo "1. 开机自启服务"; systemctl list-unit-files --type=service --state=enabled
        echo -e "\n2. 内存使用"; free -h
        echo -e "\n3. 监听端口"; ss -tulnp
        echo -e "\n4. BBR/qdisc"; sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc 2>/dev/null || echo "N/A"
    } >> "${LOG_FILE}" 2>&1

    # 2. 服务精简
    info_sep "【执行服务精简】"
    safe_disable cloud-config cloud-final cloud-init-local cloud-init
    safe_disable snap.lxd.activate snapd.apparmor snapd.autoimport snapd.core-fixup \
                 snapd.recovery-chooser-trigger snapd.seeded snapd snapd.system-shutdown
    safe_disable blk-availability e2scrub_reap lvm2-monitor multipathd open-iscsi
    safe_disable console-setup dmesg finalrd grub-common grub-initrd-fallback \
                 keyboard-setup lxd-agent setvtrgb systemd-pstore systemd-networkd-wait-online

    # 仅物理机才禁用虚拟化代理；VM 上必须保留（宿主管理/网络依赖）
    if [ "${IS_VM}" -eq 1 ]; then
        info_print "⚠️  检测到虚拟机环境，保留 qemu-guest-agent/open-vm-tools"
    else
        safe_disable open-vm-tools vgauth qemu-guest-agent
        info_print "✅ 物理机环境，已禁用虚拟化代理"
    fi

    # 安全更新策略（仅安全补丁）
    info_print "⚙️  配置 unattended-upgrades 仅安装安全补丁..."
    mkdir -p /etc/apt/apt.conf.d/
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
    systemctl enable --now unattended-upgrades.service 2>/dev/null || true
    info_print "✅ 安全自动更新已启用"

    # irqbalance（保留启用；不写死 banirq，避免禁错机器相关的中断号）
    if command -v irqbalance &>/dev/null; then
        cat > /etc/default/irqbalance << 'EOF'
IRQBALANCE_ONESHOT=no
IRQBALANCE_ARGS=""
EOF
        systemctl enable --now irqbalance.service 2>/dev/null || true
        info_print "✅ irqbalance 已启用"
    fi

    # 3. 卸载冗余包（VM 上不动 guest agent / open-iscsi 等宿主相关包）
    info_sep "【卸载冗余软件包】"
    PURGE_PKGS=(pollinate ubuntu-advantage-tools)
    if [ "${IS_VM}" -eq 0 ]; then
        PURGE_PKGS+=(multipath-tools open-iscsi open-vm-tools qemu-guest-agent)
    fi
    apt remove -y "${PURGE_PKGS[@]}" 2>/dev/null || true
    apt autoremove -y --purge 2>/dev/null || true
    apt autoclean 2>/dev/null || true
    info_print "✅ 软件包清理完成（VM 保留 guest agent: $([ "${IS_VM}" -eq 1 ] && echo 是 || echo 否)）"

    # 4. Journald 日志优化
    info_sep "【配置系统日志持久化 + 轮转策略】"
    cat > /etc/systemd/journald.conf << 'EOF'
[Journal]
Storage=persistent
Compress=yes
Seal=yes
SplitMode=uid
SyncIntervalSec=5m
RuntimeMaxUse=200M
SystemMaxUse=500M
SystemMaxFiles=10
MaxRetentionSec=7day
ForwardToSyslog=no
EOF
    systemctl restart systemd-journald 2>/dev/null || true
    journalctl --vacuum-time=7d --vacuum-size=500M 2>/dev/null || true
    info_print "✅ journald 持久化日志配置生效"

    # 5. 内核参数优化
    info_sep "【部署 VPN 内核网络优化参数】"
    cat > /etc/sysctl.d/99-vpn-tune.conf << 'EOF'
# ===== 基础转发 =====
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# ===== TCP 优化 =====
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fastopen = 3

# ===== 连接跟踪 =====
net.netfilter.nf_conntrack_max = 2097152
net.netfilter.nf_conntrack_buckets = 524288
net.netfilter.nf_conntrack_tcp_timeout_established = 432000

# ===== UDP 缓冲区（AmneziaWG/WireGuard 走 UDP，受益明显）=====
net.core.rmem_max = 25165824
net.core.wmem_max = 25165824
net.core.rmem_default = 16777216
net.core.wmem_default = 16777216
net.ipv4.udp_mem = 16777216 16777216 16777216

# ===== BBR + 队列（对外网卡；awg0 的 HTB 由限速脚本单独设置，互不影响）=====
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_limit_output_bytes = 262144

# ===== 端口 + 文件描述符 =====
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
    # nf_conntrack 模块若未加载，相关键会报错；先尝试加载再应用
    modprobe nf_conntrack 2>/dev/null || true
    sysctl -p /etc/sysctl.d/99-vpn-tune.conf 2>&1 | tee -a "${LOG_FILE}" || true
    info_print "✅ 内核网络参数加载完成"

    # 6. CPU/网卡基础优化（兼容单核/虚拟机）
    info_sep "【CPU/网卡基础优化】"
    if [ "${CPU_COUNT}" -gt 1 ] && command -v cpufreq-set &>/dev/null; then
        cpufreq-set -g performance 2>/dev/null && info_print "✅ CPU 已设为 performance 模式" || true
    fi
    if [ -n "${WAN_INTERFACE}" ] && [ -d "/sys/class/net/${WAN_INTERFACE}/queues" ]; then
        ethtool -L "${WAN_INTERFACE}" combined "${CPU_COUNT}" 2>/dev/null && \
            info_print "✅ 网卡 ${WAN_INTERFACE} 队列已设为 ${CPU_COUNT}" || true
    fi

    # 7. systemd 资源限制（适配 AmneziaWG + 本项目服务）
    info_sep "【配置 VPN 服务资源限制】"
    for svc_template in "awg-quick@awg0" "wstunnel" "vpn-api"; do
        if systemctl list-unit-files "${svc_template}.service" 2>/dev/null | grep -q .; then
            mkdir -p "/etc/systemd/system/${svc_template}.service.d/"
            cat > "/etc/systemd/system/${svc_template}.service.d/limits.conf" << 'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=65535
TasksMax=65535
OOMScoreAdjust=-500
Restart=on-failure
RestartSec=5s
EOF
            info_print "✅ 已配置 ${svc_template} 资源限制"
        else
            info_print "ℹ️  ${svc_template} 未安装，跳过资源限制"
        fi
    done
    systemctl daemon-reload 2>/dev/null || true

    # 8. 优化后验证
    info_sep "【关键指标验证结果】"
    local pass=0 fail=0
    BBR=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    [ "${BBR}" = "bbr" ] && { info_print "✅ BBR: 已启用"; pass=$((pass+1)); } || { info_print "❌ BBR 未生效"; fail=$((fail+1)); }
    RMEM=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 0)
    [ "${RMEM}" -ge 16777216 ] && { info_print "✅ UDP 缓冲区: ${RMEM} bytes"; pass=$((pass+1)); } || { info_print "⚠️  UDP 缓冲区: ${RMEM}"; pass=$((pass+1)); }
    CONN=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo 0)
    [ "${CONN}" -ge 1000000 ] && { info_print "✅ 连接跟踪表: ${CONN}"; pass=$((pass+1)); } || { info_print "⚠️  连接跟踪表: ${CONN}"; pass=$((pass+1)); }
    grep -q aes /proc/cpuinfo 2>/dev/null && { info_print "✅ CPU AES-NI: 支持"; pass=$((pass+1)); } || { info_print "⚠️  CPU AES-NI: 未检测到"; pass=$((pass+1)); }
    info_print "\n📊 验证汇总: ${pass} 通过 / ${fail} 失败"

    # 9. 收尾
    info_sep "【✅ 系统优化全部完成】"
    info_print "📄 完整日志: ${LOG_FILE}"
    info_print "🔄 回滚脚本: ${BACKUP_DIR}/rollback.sh"
    info_print "\n🔧 建议后续操作:"
    info_print "  1. 重启使内核参数完全生效:  sudo reboot"
    info_print "  2. 验证隧道:  awg show && systemctl status awg-quick@awg0 wstunnel vpn-api"
    info_print "  3. 异常回滚:  bash ${BACKUP_DIR}/rollback.sh"
}

main "$@"
