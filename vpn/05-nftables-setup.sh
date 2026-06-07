#!/bin/bash
# 05-nftables-setup.sh — nftables 防火墙策略
# 修复：动态追加规则重启后丢失（全部写入 conf 文件），
#       per-IP 连接限制语法修正（用 meter 替代不正确的 ct count）
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

apt-get install -y nftables

# 读取 WireGuard 安装时检测的 WAN 网卡
WAN_IF_FILE="/etc/wireguard/.wan-interface"
if [[ -f "${WAN_IF_FILE}" ]]; then
    WAN_IF=$(cat "${WAN_IF_FILE}")
else
    WAN_IF=$(ip -4 route show default | awk '{print $5; exit}')
fi
[[ -z "${WAN_IF}" ]] && { echo "ERROR: 无法确定 WAN 网卡"; exit 1; }
echo "  WAN 网卡: ${WAN_IF}"

# 写入完整持久化规则集（修复原框架：nft add 命令追加的规则不写入 conf 文件，重启后丢失）
cat > /etc/nftables.conf << NFTEOF
#!/usr/sbin/nft -f
flush ruleset

table inet enterprise-fw {

    # ── per-IP 并发连接计数器（修复原框架 ct count 语法错误）─────────────
    # meter 是 nftables 正确的 per-key 状态计数方式
    set tcp443_connlimit {
        type ipv4_addr
        flags dynamic
    }

    set udp51820_connlimit {
        type ipv4_addr
        flags dynamic
    }

    chain input {
        type filter hook input priority filter; policy drop;

        # 允许本地回环
        iif lo accept

        # 允许已建立/关联连接（状态跟踪，无需重复检查）
        ct state established,related accept

        # 丢弃无效包（RST洪水、序号异常等）
        ct state invalid drop

        # ── ICMP（允许基础 ping，便于运维）───────────────────────────────
        ip  protocol icmp  icmp  type { echo-request, echo-reply, destination-unreachable, time-exceeded } accept
        ip6 nexthdr  icmpv6 accept

        # ── SSH 运维端口（严格限速：每分钟 5 次新连接）──────────────────
        tcp dport 22 ct state new limit rate 5/minute burst 10 packets accept

        # ── HTTP 80（certbot 续期验证 + HTTP→HTTPS 跳转）────────────────────
        tcp dport 80 ct state new accept

        # ── Nginx HTTPS 443 端口 ──────────────────────────────────────────
        # per-IP 最多 100 并发连接（防单 IP 连接耗尽）
        tcp dport 443 ct state new \
            add @tcp443_connlimit { ip saddr ct count over 100 } drop
        tcp dport 443 ct state new accept

        # ── AmneziaWG UDP 51820（内部固定端口）───────────────────────────
        # 外部动态端口由 iptables DNAT 在 PREROUTING 阶段重写为 51820，
        # 到达此链时已是 51820，无需在此开放动态端口范围。
        # per-IP 最多 10 并发 session（单用户正常用量）
        udp dport 51820 \
            add @udp51820_connlimit { ip saddr ct count over 10 } drop
        udp dport 51820 accept

        # 其余全部丢弃（policy drop 已覆盖，此行为明确意图）
        drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;

        # 允许已建立连接的转发
        ct state established,related accept

        # TCP MSS 钳位：防止 WireGuard MTU(1420) 导致大包被丢弃
        # nftables 用「值 / 掩码」表达 iptables 的 --tcp-flags SYN,RST SYN
        tcp flags syn / syn,rst tcp option maxseg size set 1360

        # 允许 WireGuard 子网出站（VPN 客户端访问公网）
        ip saddr 10.200.0.0/21 oif ${WAN_IF} accept

        # 允许 WireGuard 子网内互访（可选：内网隔离时注释此行）
        ip saddr 10.200.0.0/21 ip daddr 10.200.0.0/21 accept
    }

    chain output {
        type filter hook output priority filter; policy accept;
        # 出站默认全放行（服务器发起的连接不限制）
    }

    # ── NAT 表（WireGuard 客户端流量出站伪装）────────────────────────────
    # 注意：WireGuard PostUp iptables 规则已处理 NAT，此处为 nftables 对等方案
    # 若 wg-quick 使用 iptables，此 nat 链留空即可，二者不冲突
    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        ip saddr 10.200.0.0/21 oif ${WAN_IF} masquerade
    }
}
NFTEOF

# 语法校验
nft -c -f /etc/nftables.conf && echo "  nftables 规则语法验证通过"

# 加载规则
nft -f /etc/nftables.conf

# 启用服务（开机自动加载 /etc/nftables.conf）
systemctl enable --now nftables
systemctl restart nftables

echo ""
echo "nftables 防火墙策略已部署（持久化至 /etc/nftables.conf）："
echo "  入站放行端口: TCP 22 (SSH 限速), TCP 80 (HTTP/certbot), TCP 443 (HTTPS), UDP 51820 (AmneziaWG 内部)"
echo "  WireGuard 子网: 10.200.0.0/21 NAT 出站通过 ${WAN_IF}"
echo "  per-IP 并发: 443 ≤ 100连接，51820 ≤ 10连接"
echo "  动态端口跳变: 由 iptables AWG_HOP 链 DNAT 至 51820，nftables 无需感知"
echo "  其余入站: 全部丢弃"
