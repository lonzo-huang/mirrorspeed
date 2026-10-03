#!/bin/bash
# fix-subnet-acl.sh — 把 nftables 的隧道网段放行/NAT 统一到 10.200.0.0/16。
#
# 背景：地址池经历过 /24 → /21 → /16 两次扩容（见 05-nftables-setup.sh 的演进）。
# 在扩容之前装机、之后没重跑过 05 脚本的节点，enterprise-fw 的 forward 链仍只放行
# 旧网段，而 forward 的 policy 是 drop。于是：
#   · 老用户（10.200.0.x）在放行范围内 → 一切正常，完全无感
#   · 用户数超过 254 后新分到 10.200.1.x 的用户 → 握手走 INPUT 的 51820 不受影响，
#     能"连上"，但数据包一律被静默丢弃 → 表现为"已连接但流量不通"
# 症状极具迷惑性：同一账号换节点/换设备/删号重建都一样，而别人用同一节点却没事。
#
# 本脚本可在任意节点、任意版本、任意次数重复执行，无副作用：
#   · 出口网卡按默认路由现算，不写死
#   · 插规则前先查重，不会堆积
#   · 无 enterprise-fw（纯 iptables 的老节点，forward 默认 ACCEPT）时跳过
#   · 改 /etc/nftables.conf 前备份，nft -c 校验不过自动回滚
#   · 全程不 restart nftables —— 重启会 flush 掉端口跳变的 AWG_HOP 链
set -e
[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

SUBNET=10.200.0.0/16
CONF=/etc/nftables.conf

WAN=$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1); exit}')
[ -n "$WAN" ] || { echo "❌ 找不到默认路由网卡"; exit 1; }
echo "出口网卡: $WAN"

# 1) 内存规则
if nft list chain inet enterprise-fw forward >/dev/null 2>&1; then
  if nft list chain inet enterprise-fw forward | grep -q "$SUBNET"; then
    echo "✓ forward 链已放行 $SUBNET"
  else
    nft insert rule inet enterprise-fw forward ip saddr $SUBNET oif "$WAN" accept
    nft insert rule inet enterprise-fw forward ip saddr $SUBNET ip daddr $SUBNET accept
    echo "✓ 已补 forward 放行"
  fi
  if nft list chain inet enterprise-fw postrouting 2>/dev/null | grep -q "$SUBNET"; then
    echo "✓ postrouting 链已 NAT $SUBNET"
  else
    nft insert rule inet enterprise-fw postrouting ip saddr $SUBNET oif "$WAN" masquerade 2>/dev/null \
      && echo "✓ 已补 postrouting NAT" || echo "· 无 postrouting 链，跳过"
  fi
else
  echo "· 本机无 enterprise-fw（转发默认放行），无需补规则"
fi

# 2) 持久化文件
if [ -f "$CONF" ] && grep -qE '10\.200\.0\.0/(24|21)' "$CONF"; then
  BAK="$CONF.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONF" "$BAK"
  sed -i -E 's#10\.200\.0\.0/(24|21)#'"$SUBNET"'#g' "$CONF"
  if nft -c -f "$CONF" >/dev/null 2>&1; then
    echo "✓ $CONF 已更新为 $SUBNET（备份 $BAK）"
  else
    cp "$BAK" "$CONF"
    echo "❌ 改完语法不过，已回滚，请人工检查"; exit 1
  fi
else
  echo "✓ $CONF 无需修改"
fi

# 3) 转发开关
sysctl -qw net.ipv4.ip_forward=1
grep -qs '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

echo "—— 完成 ——"
