#!/usr/bin/env python3
"""
ms-free-nodes.py — 抓取机场订阅 → 解析 → upsert 到 Supabase free_nodes。

在控制机(VM01-FRA-DE)上由 systemd timer 定时跑(建议 5–10 分钟一次)。
- 拉订阅源(base64 节点列表)
- node_parser 解析成 sing-box outbound
- upsert(按 fingerprint 去重):在库=刷新 last_seen；新的=插入
- 连续 N 小时没再抓到的节点 → is_active=false（不删,便于观察/复活）

纯标准库 + node_parser。配置:/etc/mirrorspeed/free-nodes.env
"""

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import node_parser  # noqa: E402

CONF = '/etc/mirrorspeed/free-nodes.env'
ENV = {}
try:
    with open(CONF) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                ENV[k] = v.strip().strip('"')
except OSError as e:
    print(f'[free-nodes] cannot read {CONF}: {e}', file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = ENV.get('SUPABASE_URL', '').rstrip('/')
SERVICE_KEY  = ENV.get('SUPABASE_SERVICE_KEY', '')
SUB_URL      = ENV.get('FREE_NODES_SUB_URL', '')
STALE_HOURS  = int(ENV.get('FREE_NODES_STALE_HOURS', '6'))

if not (SUPABASE_URL and SERVICE_KEY and SUB_URL):
    print('[free-nodes] SUPABASE_URL / SUPABASE_SERVICE_KEY / FREE_NODES_SUB_URL missing', file=sys.stderr)
    sys.exit(1)


def sb(method: str, path: str, body=None, prefer: str = None):
    url = f'{SUPABASE_URL}/rest/v1/{path}'
    data = json.dumps(body).encode() if body is not None else None
    headers = {
        'apikey':        SERVICE_KEY,
        'Authorization': f'Bearer {SERVICE_KEY}',
        'Content-Type':  'application/json',
    }
    if prefer:
        headers['Prefer'] = prefer
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def fetch_subscription() -> str:
    req = urllib.request.Request(SUB_URL, headers={'User-Agent': 'ms-free-nodes/1.0'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode('utf-8', 'ignore')


def main() -> None:
    try:
        text = fetch_subscription()
    except Exception as e:
        print(f'[free-nodes] fetch failed: {e}', file=sys.stderr)
        sys.exit(1)

    nodes = node_parser.parse_subscription(text)
    if not nodes:
        print('[free-nodes] parsed 0 nodes (source empty or format changed)', file=sys.stderr)
        sys.exit(1)

    now = datetime.now(timezone.utc).isoformat()
    rows = [{
        'fingerprint': n['fingerprint'],
        'protocol':    n['protocol'],
        'name':        n['name'][:120],
        'server':      n['server'],
        'port':        n['port'],
        'outbound':    n['outbound'],
        'is_active':   True,
        'last_seen':   now,
    } for n in nodes]

    # upsert：on_conflict=fingerprint，merge-duplicates 用 body 覆盖(刷新 last_seen/is_active)
    try:
        sb('POST', 'free_nodes?on_conflict=fingerprint', rows,
           prefer='resolution=merge-duplicates,return=minimal')
    except Exception as e:
        print(f'[free-nodes] upsert failed: {e}', file=sys.stderr)
        sys.exit(1)

    # 把太久没再抓到的节点下架(不删)
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=STALE_HOURS)).isoformat()
    try:
        sb('PATCH', f'free_nodes?is_active=eq.true&last_seen=lt.{cutoff}',
           {'is_active': False}, prefer='return=minimal')
    except Exception as e:
        print(f'[free-nodes] stale-off failed (non-fatal): {e}', file=sys.stderr)

    # 统计当前活跃数
    active = sb('GET', 'free_nodes?is_active=eq.true&select=id') or []
    print(f'[free-nodes] parsed={len(nodes)} upserted={len(rows)} active_total={len(active)}')


if __name__ == '__main__':
    main()
