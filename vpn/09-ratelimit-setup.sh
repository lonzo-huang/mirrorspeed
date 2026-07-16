#!/bin/bash
# 09-ratelimit-setup.sh — 按用户分级限速（免费/付费/超级）
#
# 设计：tc(HTB) 静态分层 + ipset 动态成员 + fwmark 打标。
#   - 限「下行」（服务器→客户端，即客户端的下载速度）：tc 挂在 AmneziaWG 接口(awg0) egress。
#   - 免费用户 IP → ipset ms_free → mangle 打 0x1 → tc 1:10（free_mbit）
#   - 付费用户 IP → ipset ms_paid → mangle 打 0x2 → tc 1:20（paid_mbit）
#   - 超级/未知（未打标）→ tc 默认 1:30（super_mbit；0=满速）
#   - 限速值与用户分级由 Supabase RPC get_ratelimit_config 下发（本机用公开 anon key 直连，不经 Vercel）。
#   - systemd timer 每 60s 同步一次（成员秒级、限速值改即生效）。
#
# 幂等：可重复运行；自动探测网卡，无需手填。
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "ERROR: 必须以 root 执行"; exit 1; }

API_BASE="${API_BASE:-https://www.mirrorspeed.com}"
# 限速配置改为直连 Supabase RPC（get_ratelimit_config），不再走 Vercel。anon key 为公开 key。
SUPABASE_URL="${SUPABASE_URL:-https://yqckjzfwibklwokialac.supabase.co}"
SUPABASE_ANON="${SUPABASE_ANON:-eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxY2tqemZ3aWJrbHdva2lhbGFjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkxOTY1MzcsImV4cCI6MjA5NDc3MjUzN30.NDxrGI6mgVMjgJvBchTkOCcT_ldiEEWtpJkFOhFGYNA}"
LINK_MBIT="${LINK_MBIT:-1000}"                 # 服务器出口总带宽（HTB 满速类 ceil）
VPNAPI_ENV="/opt/mirrorspeed/vpn-api/.env"
CONF_DIR="/etc/mirrorspeed"
SYNC_BIN="/usr/local/bin/ms-ratelimit-sync.py"

echo "[1/6] 安装依赖 ipset..."
apt-get install -y -qq ipset >/dev/null

echo "[2/6] 自动探测 AmneziaWG 接口..."
WG_IFACE="$(awg show interfaces 2>/dev/null | awk '{print $1}')"
[[ -z "${WG_IFACE}" ]] && WG_IFACE="awg0"
[[ -d "/sys/class/net/${WG_IFACE}" ]] || { echo "ERROR: 未找到 WG 接口 ${WG_IFACE}（先装好 AmneziaWG）"; exit 1; }
echo "  WG 接口: ${WG_IFACE}"

echo "[3/6] 读取本机 api_secret..."
VPN_API_SECRET="${VPN_API_SECRET:-}"
if [[ -z "${VPN_API_SECRET}" && -f "${VPNAPI_ENV}" ]]; then
    VPN_API_SECRET="$(grep -E '^VPN_API_SECRET=' "${VPNAPI_ENV}" | cut -d= -f2- | tr -d '\r"')"
fi
[[ -z "${VPN_API_SECRET}" ]] && { echo "ERROR: 找不到 api_secret（${VPNAPI_ENV} 缺失？可用 VPN_API_SECRET=... 传入）"; exit 1; }

echo "[4/6] 写入配置 ${CONF_DIR}/ratelimit.env..."
mkdir -p "${CONF_DIR}"
cat > "${CONF_DIR}/ratelimit.env" <<ENVEOF
API_BASE=${API_BASE}
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON=${SUPABASE_ANON}
VPN_API_SECRET=${VPN_API_SECRET}
WG_IFACE=${WG_IFACE}
LINK_MBIT=${LINK_MBIT}
ENVEOF
chmod 600 "${CONF_DIR}/ratelimit.env"

echo "[5/6] 安装同步脚本 ${SYNC_BIN}..."
cat > "${SYNC_BIN}" <<'PYEOF'
#!/usr/bin/env python3
# ms-ratelimit-sync.py — 从 Supabase RPC 拉取限速值 + 各档 IP，应用 tc/ipset/iptables。
import json, os, subprocess, sys, urllib.request

ENV = {}
with open('/etc/mirrorspeed/ratelimit.env') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            ENV[k] = v.strip().strip('"')

SUPABASE_URL  = ENV.get('SUPABASE_URL', '').rstrip('/')
SUPABASE_ANON = ENV.get('SUPABASE_ANON', '')
IFACE    = ENV.get('WG_IFACE', 'awg0')
LINK     = int(ENV.get('LINK_MBIT', '1000') or '1000')
STATE    = '/run/ms-ratelimit.rates'

def sh(cmd):
    return subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode

def fetch():
    # 直连 Supabase RPC（get_ratelimit_config），用公开 anon key。DB 内部算好三档，
    # 只返回聚合 IP 列表，绕开 Vercel。
    req = urllib.request.Request(
        f'{SUPABASE_URL}/rest/v1/rpc/get_ratelimit_config',
        data=b'{}',
        headers={
            'apikey':        SUPABASE_ANON,
            'Authorization': f'Bearer {SUPABASE_ANON}',
            'Content-Type':  'application/json',
        },
        method='POST',
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)

def ensure_ipset(name):
    sh(f'ipset create {name} hash:ip family inet -exist')

def swap_ipset(name, ips):
    tmp = f'{name}_tmp'
    sh(f'ipset create {tmp} hash:ip family inet -exist')
    sh(f'ipset flush {tmp}')
    if ips:
        data = ''.join(f'add {tmp} {ip}\n' for ip in ips).encode()
        p = subprocess.Popen(['ipset', 'restore'], stdin=subprocess.PIPE,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p.communicate(data)
    ensure_ipset(name)
    sh(f'ipset swap {tmp} {name}')
    sh(f'ipset destroy {tmp}')

def ensure_tc(free, paid, sup):
    # mbit<=0 视为不限速 → 该类速率用满速 LINK
    fr = free if free > 0 else LINK
    pr = paid if paid > 0 else LINK
    dr = sup  if sup  > 0 else LINK
    sig = f'{fr},{pr},{dr},{LINK}'
    have = sh(f'tc qdisc show dev {IFACE} | grep -q "htb 1:"') == 0
    last = ''
    try:
        last = open(STATE).read().strip()
    except OSError:
        pass
    if have and last == sig:
        return
    sh(f'tc qdisc del dev {IFACE} root')
    sh(f'tc qdisc add dev {IFACE} root handle 1: htb default 30')
    sh(f'tc class add dev {IFACE} parent 1: classid 1:1 htb rate {LINK}mbit ceil {LINK}mbit')
    sh(f'tc class add dev {IFACE} parent 1:1 classid 1:10 htb rate {fr}mbit ceil {fr}mbit')
    sh(f'tc class add dev {IFACE} parent 1:1 classid 1:20 htb rate {pr}mbit ceil {pr}mbit')
    sh(f'tc class add dev {IFACE} parent 1:1 classid 1:30 htb rate {dr}mbit ceil {dr}mbit')
    for h in (10, 20, 30):
        sh(f'tc qdisc add dev {IFACE} parent 1:{h} handle {h}: fq_codel')
    sh(f'tc filter add dev {IFACE} parent 1: protocol ip prio 1 handle 0x1 fw flowid 1:10')
    sh(f'tc filter add dev {IFACE} parent 1: protocol ip prio 1 handle 0x2 fw flowid 1:20')
    try:
        open(STATE, 'w').write(sig)
    except OSError:
        pass

def ensure_iptables():
    # 给「出 WG 接口、目的=某档 IP」的包打标（= 客户端下载方向）。幂等：-C 不存在才 -A。
    for setname, mark in (('ms_free', '0x1'), ('ms_paid', '0x2')):
        spec = f'POSTROUTING -o {IFACE} -m set --match-set {setname} dst -j MARK --set-mark {mark}'
        if sh(f'iptables -t mangle -C {spec}') != 0:
            sh(f'iptables -t mangle -A {spec}')

def main():
    try:
        data = fetch()
    except Exception as e:
        print(f'[ratelimit] fetch failed: {e}', file=sys.stderr)
        sys.exit(1)
    free = int(data.get('free_mbit', 4))
    paid = int(data.get('paid_mbit', 10))
    sup  = int(data.get('super_mbit', 0))
    ensure_ipset('ms_free')
    ensure_ipset('ms_paid')
    ensure_tc(free, paid, sup)
    ensure_iptables()
    swap_ipset('ms_free', data.get('free_ips', []) if free > 0 else [])
    swap_ipset('ms_paid', data.get('paid_ips', []) if paid > 0 else [])
    print(f"[ratelimit] free={free} paid={paid} super={sup} "
          f"| free_ips={len(data.get('free_ips', []))} paid_ips={len(data.get('paid_ips', []))}")

if __name__ == '__main__':
    main()
PYEOF
chmod +x "${SYNC_BIN}"

echo "[6/6] 安装 systemd 服务 + 定时器（每 60s）..."
cat > /etc/systemd/system/ms-ratelimit.service <<'UNITEOF'
[Unit]
Description=MirrorSpeed per-tier rate limit sync
After=network-online.target awg-quick@awg0.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/bin/ms-ratelimit-sync.py
UNITEOF

cat > /etc/systemd/system/ms-ratelimit.timer <<'TIMEREOF'
[Unit]
Description=Run MirrorSpeed rate limit sync every 60s

[Timer]
OnBootSec=30
OnUnitActiveSec=60
AccuracySec=5s

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now ms-ratelimit.timer >/dev/null 2>&1 || true
# 立即跑一次
systemctl start ms-ratelimit.service || true

echo ""
echo "限速部署完成："
echo "  WG 接口:   ${WG_IFACE}（限下行）"
echo "  出口带宽:  ${LINK_MBIT} Mbit"
echo "  限速值/分级: 来自 Supabase RPC get_ratelimit_config（直连，不经 Vercel；app_config 可改）"
echo "  同步频率:  每 60s（systemd: ms-ratelimit.timer）"
echo ""
echo "  查看状态:  systemctl status ms-ratelimit.timer"
echo "  手动同步:  systemctl start ms-ratelimit.service && journalctl -u ms-ratelimit.service -n 5 --no-pager"
echo "  查看 tc:   tc -s class show dev ${WG_IFACE}"
echo "  查看 ipset: ipset list ms_free; ipset list ms_paid"
