#!/usr/bin/env python3
"""
从 sing-box 官方 geoip-cn 规则集生成优质节点(WireGuard)智能模式用的中国 IP 段表。

  assets/routes/cn_cidr.txt  ← 本脚本输出

WireGuard 的智能模式是把「中国以外的所有 IP 段」写成 AllowedIPs 路由，中国段越精细
路由条数越多：全量 geoip-cn 约 1.2 万条，Windows 上逐条加系统路由会明显拖慢连接。
所以按 /15 向上合并，在精度和路由条数之间折中（约 1500 条）。

用法（在 client/ 下，需 sing-box CLI）：
  python3 tool/gen_cn_cidr.py                 # 默认 /15
  python3 tool/gen_cn_cidr.py --prefix 16     # 更精细，路由更多
规则集来源：ios_macos_native/RuleSets/geoip-cn.srs（与免费节点共用同一份数据）
"""
import argparse, datetime, ipaddress, json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.dirname(HERE)
SRS = os.path.join(CLIENT, 'ios_macos_native', 'RuleSets', 'geoip-cn.srs')
OUT = os.path.join(CLIENT, 'assets', 'routes', 'cn_cidr.txt')


def complement(nets):
    out = [ipaddress.ip_network('0.0.0.0/0')]
    for n in nets:
        nxt = []
        for a in out:
            if a.overlaps(n):
                if a.subnet_of(n):
                    continue
                nxt.extend(a.address_exclude(n))
            else:
                nxt.append(a)
        out = nxt
    return list(ipaddress.collapse_addresses(out))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prefix', type=int, default=15, help='向上合并到的最小前缀长度')
    ap.add_argument('--sing-box', default=os.environ.get('SING_BOX', 'sing-box'))
    args = ap.parse_args()

    with tempfile.TemporaryDirectory() as tmp:
        js = os.path.join(tmp, 'geoip-cn.json')
        subprocess.run([args.sing_box, 'rule-set', 'decompile', SRS, '-o', js], check=True)
        cidrs = json.load(open(js))['rules'][0]['ip_cidr']

    v4 = [ipaddress.ip_network(c) for c in cidrs if ':' not in c]
    p = args.prefix
    merged = list(ipaddress.collapse_addresses(
        n.supernet(new_prefix=p) if n.prefixlen > p else n for n in v4))
    routes = complement(merged)

    today = datetime.date.today().isoformat()
    with open(OUT, 'w') as f:
        f.write('# China Mainland IP Ranges — Smart Mode\n')
        f.write('# Traffic matching these ranges goes DIRECT (bypasses VPN).\n')
        f.write('# Everything else is routed through the VPN tunnel.\n')
        f.write(f'# Generated {today} by tool/gen_cn_cidr.py from sing-box geoip-cn,\n')
        f.write(f'# merged to /{p}: {len(merged)} CN ranges -> {len(routes)} tunnel routes.\n')
        f.write('# Do not edit by hand; re-run the script instead.\n')
        for n in merged:
            f.write(f'{n}\n')
    print(f'✅ {OUT}\n   中国段 {len(merged)} 条 → 智能模式路由 {len(routes)} 条（/{p} 合并）')


if __name__ == '__main__':
    sys.exit(main())
