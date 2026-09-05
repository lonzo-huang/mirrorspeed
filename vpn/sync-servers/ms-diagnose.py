#!/usr/bin/env python3
"""
ms-diagnose.py — 节点「离线」诊断（只读，不改数据库）

在**控制机**上运行（和 ms-sync-servers.py 同机、同配置）：
    sudo python3 ms-diagnose.py

它会：
  1. 读 /etc/mirrorspeed/sync-servers.env（SUPABASE_URL + SUPABASE_SERVICE_KEY）
  2. 从 Supabase 列出所有 active 节点（名字/status/api_url/last_checked_at）
  3. 逐个探测节点管理 API 的 /stats 和 /health（就是健康检查用的那两个接口）
  4. 明确区分：
       - 管理 API 连不上   → 监控通道问题（客户端数据面可能仍正常，误标 offline 的元凶）
       - /health wg 已 down → 隧道真死（客户端也连不上）
       - 都正常             → 节点健康
只读，不写库；你不用记任何密钥。
"""

import json, sys, urllib.error, urllib.request
from datetime import datetime, timezone

CONF = '/etc/mirrorspeed/sync-servers.env'

ENV = {}
try:
    with open(CONF) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                ENV[k] = v.strip().strip('"')
except OSError as e:
    print(f'cannot read {CONF}: {e}', file=sys.stderr); sys.exit(1)

SUPABASE_URL = ENV.get('SUPABASE_URL', '').rstrip('/')
SERVICE_KEY  = ENV.get('SUPABASE_SERVICE_KEY', '')
TIMEOUT      = int(ENV.get('SERVER_TIMEOUT', '8'))
if not SUPABASE_URL or not SERVICE_KEY:
    print('SUPABASE_URL / SUPABASE_SERVICE_KEY missing', file=sys.stderr); sys.exit(1)


def sb_get(path_and_query: str):
    req = urllib.request.Request(
        f'{SUPABASE_URL}/rest/v1/{path_and_query}',
        headers={'apikey': SERVICE_KEY, 'Authorization': f'Bearer {SERVICE_KEY}'})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def probe(url: str, secret: str = None):
    """返回 (ok, detail)。ok=False 说明管理 API 不可达（或返回错误）。"""
    headers = {'X-API-Secret': secret} if secret else {}
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return True, json.load(r)
    except urllib.error.HTTPError as e:
        return False, f'HTTP {e.code}'
    except Exception as e:
        return False, f'{type(e).__name__}: {e}'


def main():
    servers = sb_get('vpn_servers?is_active=eq.true'
                     '&select=id,name,api_url,api_secret,status,load_percent,last_checked_at'
                     '&order=name')
    if not servers:
        print('no active servers'); return

    print(f'共 {len(servers)} 个 active 节点\n' + '=' * 70)
    problems = []
    for s in servers:
        name    = s.get('name') or s.get('id')
        api_url = (s.get('api_url') or '').rstrip('/')
        secret  = s.get('api_secret')
        db_stat = s.get('status')
        last    = s.get('last_checked_at') or '-'

        print(f'\n▶ {name}   [DB status={db_stat}  load={s.get("load_percent")}%  last_checked={last}]')
        print(f'   api_url = {api_url or "(空!)"}')
        if not api_url:
            print('   ✗ api_url 为空 → 健康检查必然异常 → 兜底标 offline')
            problems.append((name, 'api_url 为空'))
            continue
        if not secret:
            print('   ✗ api_secret 为空 → /stats 会因缺密钥抛异常 → 兜底标 offline')
            problems.append((name, 'api_secret 为空'))
            continue

        ok_stats, d_stats = probe(f'{api_url}/stats', secret)
        ok_health, d_health = probe(f'{api_url}/health')

        if not ok_stats:
            print(f'   ✗ /stats 不可达：{d_stats}')
            print('   → 监控通道问题（控制机连不上节点管理 API）。客户端数据面可能仍正常，'
                  '这就是被误标 offline 的原因。')
            problems.append((name, f'/stats 不可达: {d_stats}'))
        else:
            ap = d_stats.get('active_peers'); cpu = d_stats.get('cpu_percent'); mem = d_stats.get('mem_percent')
            print(f'   ✓ /stats 正常：active_peers={ap} cpu={cpu}% mem={mem}%')

        wg = (d_health or {}).get('wg_status') if ok_health else None
        if not ok_health:
            print(f'   · /health 不可达：{d_health}（无鉴权接口，通常也说明管理端口不通）')
        elif wg == 'down':
            print('   ✗ /health wg_status=down → 隧道真的死了（客户端也会连不上，需重启节点 WG）')
            problems.append((name, '隧道 wg down'))
        else:
            print(f'   ✓ /health wg_status={wg}')

    print('\n' + '=' * 70)
    if problems:
        print('有问题的节点：')
        for n, why in problems:
            print(f'  - {n}: {why}')
        print('\n若为「/stats 不可达 / api_url|secret 为空」→ 是监控通道/配置问题，'
              '不代表节点不可用；修管理 API 或 DB 里的 api_url/api_secret 即可。')
    else:
        print('所有节点管理 API 均正常。若客户端仍显示离线，可能是 last_checked 过旧或客户端缓存。')


if __name__ == '__main__':
    main()
