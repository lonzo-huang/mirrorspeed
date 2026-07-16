#!/usr/bin/env python3
"""
ms-sync-servers.py — 节点状态同步 + 流量计量 + 免费额度封禁

从 Vercel 的 /api/cron/sync-servers 移植而来（每分钟跑一次的 cron 在 Vercel 上
是最大的一块开销：1440 次/天 × 探测 7 台 × 3 接口 + 读写 Supabase）。
现改为在「控制机」上由 systemd timer 驱动，直连 Supabase，不再经过 Vercel。

职责（与原实现保持一致）：
  1. 并发探测每台 active 服务器的 /stats /health /peers，写回 vpn_servers 状态
  2. 同步每个 peer 的今日流量用量（vpn_device_peers.daily_bytes）
  3. 评估各设备额度，对超额免费用户暂停 peer、次日或回落后恢复

依赖：仅 Python 标准库（urllib + concurrent.futures），无需 pip 安装。
配置：/etc/mirrorspeed/sync-servers.env（root 600），需 SUPABASE_URL + SUPABASE_SERVICE_KEY
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
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
    print(f'[sync] cannot read {CONF}: {e}', file=sys.stderr)
    sys.exit(1)

SUPABASE_URL = ENV.get('SUPABASE_URL', '').rstrip('/')
SERVICE_KEY  = ENV.get('SUPABASE_SERVICE_KEY', '')
SERVER_TIMEOUT = int(ENV.get('SERVER_TIMEOUT', '8'))

if not SUPABASE_URL or not SERVICE_KEY:
    print('[sync] SUPABASE_URL / SUPABASE_SERVICE_KEY missing', file=sys.stderr)
    sys.exit(1)

DEFAULT_FREE_DAILY_BYTES = 524288000   # 500MB，与原实现一致


def today_utc() -> str:
    return datetime.now(timezone.utc).strftime('%Y-%m-%d')


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ── Supabase (PostgREST) ────────────────────────────────────────────────────
def sb(method: str, path_and_query: str, body=None, timeout: int = 15):
    """path_and_query 例如 'vpn_servers?is_active=eq.true&select=id,name'"""
    url = f'{SUPABASE_URL}/rest/v1/{path_and_query}'
    data = json.dumps(body).encode() if body is not None else None
    headers = {
        'apikey':        SERVICE_KEY,
        'Authorization': f'Bearer {SERVICE_KEY}',
        'Content-Type':  'application/json',
    }
    if method in ('PATCH', 'POST'):
        headers['Prefer'] = 'return=minimal'
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        if not raw:
            return None
        try:
            return json.loads(raw)
        except ValueError:
            return None


# ── 目标服务器 API ──────────────────────────────────────────────────────────
def api_get(url: str, secret: str = None, timeout: int = None):
    headers = {'X-API-Secret': secret} if secret else {}
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout or SERVER_TIMEOUT) as r:
        return json.load(r)


def set_peer_active(api_url: str, peer_name: str, active: bool, secret: str) -> None:
    """暂停/恢复某个 peer（失败不抛出，与原实现一致，仅记日志）"""
    try:
        req = urllib.request.Request(
            f'{api_url.rstrip("/")}/peers/{urllib.parse.quote(peer_name)}/status',
            data=json.dumps({'active': active}).encode(),
            headers={'Content-Type': 'application/json', 'X-API-Secret': secret},
            method='PATCH',
        )
        urllib.request.urlopen(req, timeout=5).close()
    except Exception as e:
        print(f'[quota] setPeerActive({peer_name}, {active}) failed: {e}', file=sys.stderr)


# ── 1) 探测单台服务器并写回状态 ─────────────────────────────────────────────
def sync_one(server: dict) -> dict:
    sid     = server['id']
    name    = server.get('name') or sid
    api_url = (server.get('api_url') or '').rstrip('/')
    secret  = server.get('api_secret')
    t0 = datetime.now(timezone.utc)

    try:
        if not secret:
            raise RuntimeError('missing api_secret')

        stats  = api_get(f'{api_url}/stats', secret)
        # /health 真正执行 `awg show`——唯一能发现「隧道已死」的信号
        try:
            health = api_get(f'{api_url}/health')
        except Exception:
            health = None
        try:
            peers = api_get(f'{api_url}/peers', secret)
        except Exception:
            peers = []

        latency_ms = int((datetime.now(timezone.utc) - t0).total_seconds() * 1000)

        max_peers = server.get('max_peers') or 200
        load_pct  = round((stats.get('active_peers', 0) / max_peers) * 100)

        # 状态判定只看真实健康度，与「控制机→节点」的地理距离无关（不用延迟判 degraded）
        status = stats.get('status', 'online')
        if stats.get('cpu_percent', 0) > 90 or stats.get('mem_percent', 0) > 90:
            status = 'degraded'
        if health and health.get('wg_status') == 'down':
            status = 'offline'      # 隧道死了：必须踢出选路

        sb('PATCH', f'vpn_servers?id=eq.{sid}', {
            'status':          status,
            'latency_ms':      latency_ms,
            'active_peers':    stats.get('active_peers', 0),
            'load_percent':    min(100, load_pct),
            'cpu_percent':     stats.get('cpu_percent'),
            'mem_percent':     stats.get('mem_percent'),
            'bandwidth_mbps':  (stats.get('bw_tx_mbps', 0) or 0) + (stats.get('bw_rx_mbps', 0) or 0),
            'last_checked_at': now_iso(),
        })

        if peers:
            sync_peer_usage(sid, peers)

        return {'server': name, 'ok': True, 'status': status}

    except Exception as e:
        try:
            sb('PATCH', f'vpn_servers?id=eq.{sid}', {
                'status':          'offline',
                'latency_ms':      None,
                'last_checked_at': now_iso(),
            })
        except Exception:
            pass
        return {'server': name, 'ok': False, 'error': str(e)}


# ── 2) 同步单台服务器上各 peer 的今日流量 ───────────────────────────────────
def sync_peer_usage(server_id: str, wg_peers: list) -> None:
    today = today_utc()
    db_peers = sb('GET',
        f'vpn_device_peers?server_id=eq.{server_id}&is_active=eq.true'
        f'&select=id,peer_name,last_total_bytes,daily_bytes,daily_reset_at') or []
    if not db_peers:
        return
    by_name = {p['peer_name']: p for p in db_peers}

    for wp in wg_peers:
        dp = by_name.get(wp.get('peer_name'))
        if not dp:
            continue
        current_total = (wp.get('rx_bytes', 0) or 0) + (wp.get('tx_bytes', 0) or 0)
        last_total    = dp.get('last_total_bytes') or 0
        # WireGuard 重启后计数归零：此时 current < last，直接以 current 作为增量
        delta = current_total - last_total if current_total >= last_total else current_total

        is_new_day = (dp.get('daily_reset_at') or '') < today
        if is_new_day:
            new_daily, new_reset = delta, today
        else:
            new_daily, new_reset = (dp.get('daily_bytes') or 0) + delta, dp.get('daily_reset_at')

        sb('PATCH', f'vpn_device_peers?id=eq.{dp["id"]}', {
            'last_total_bytes': current_total,
            'daily_bytes':      new_daily,
            'daily_reset_at':   new_reset,
        })


# ── 3) 额度评估：超额免费用户暂停，付费/次日/回落则恢复 ─────────────────────
def enforce_quotas(servers: list) -> dict:
    today = today_utc()

    cfg = sb('GET', 'app_config?key=eq.free_daily_bytes&select=value') or []
    try:
        quota_bytes = int(cfg[0]['value']) if cfg else DEFAULT_FREE_DAILY_BYTES
    except (ValueError, KeyError, IndexError):
        quota_bytes = DEFAULT_FREE_DAILY_BYTES

    rows = sb('GET',
        'vpn_device_peers?is_active=eq.true&device.is_active=eq.true'
        '&select=id,peer_name,server_id,daily_bytes,daily_reset_at,is_suspended,'
        'device:vpn_devices!inner(id,user_id,is_active)') or []
    if not rows:
        return {'suspended': 0, 'resumed': 0}

    # 按 device 聚合
    devices = {}
    for p in rows:
        dev = p.get('device') or {}
        if not dev.get('is_active'):
            continue
        d = devices.setdefault(dev['id'], {'user_id': dev.get('user_id'), 'total': 0, 'peers': []})
        # 新的一天的旧计数不计入（syncPeerUsage 会重置）
        d['total'] += (p.get('daily_bytes') or 0) if (p.get('daily_reset_at') or '') >= today else 0
        d['peers'].append(p)

    user_ids = list({d['user_id'] for d in devices.values() if d.get('user_id')})
    paid = set()
    if user_ids:
        ids = ','.join(user_ids)
        subs = sb('GET', f'subscriptions?status=eq.active&user_id=in.({ids})&select=user_id') or []
        paid = {s['user_id'] for s in subs}

    api_of = {s['id']: {'url': (s.get('api_url') or '').rstrip('/'), 'secret': s.get('api_secret')}
              for s in servers}

    suspended = resumed = 0
    for d in devices.values():
        is_paid  = d['user_id'] in paid
        is_over  = (not is_paid) and d['total'] > quota_bytes
        for p in d['peers']:
            srv = api_of.get(p['server_id'])
            if not srv or not srv['secret']:
                continue
            is_new_day = (p.get('daily_reset_at') or '') < today
            susp = bool(p.get('is_suspended'))

            if is_paid and susp:
                set_peer_active(srv['url'], p['peer_name'], True, srv['secret'])
                sb('PATCH', f'vpn_device_peers?id=eq.{p["id"]}', {'is_suspended': False}); resumed += 1
            elif is_new_day and susp:
                set_peer_active(srv['url'], p['peer_name'], True, srv['secret'])
                sb('PATCH', f'vpn_device_peers?id=eq.{p["id"]}', {'is_suspended': False}); resumed += 1
            elif (not is_over) and susp:
                # 当天用量已回落到额度以下（或额度被上调）→ 立即恢复，不必等到午夜
                set_peer_active(srv['url'], p['peer_name'], True, srv['secret'])
                sb('PATCH', f'vpn_device_peers?id=eq.{p["id"]}', {'is_suspended': False}); resumed += 1
            elif is_over and not susp:
                set_peer_active(srv['url'], p['peer_name'], False, srv['secret'])
                sb('PATCH', f'vpn_device_peers?id=eq.{p["id"]}', {'is_suspended': True}); suspended += 1

    return {'suspended': suspended, 'resumed': resumed}


def main() -> None:
    try:
        servers = sb('GET',
            'vpn_servers?is_active=eq.true&select=id,name,api_url,api_secret,max_peers') or []
    except Exception as e:
        print(f'[sync] cannot load servers: {e}', file=sys.stderr)
        sys.exit(1)

    if not servers:
        print('[sync] no active servers')
        return

    with ThreadPoolExecutor(max_workers=min(16, len(servers))) as ex:
        results = list(ex.map(sync_one, servers))

    ok   = [r for r in results if r['ok']]
    bad  = [r for r in results if not r['ok']]
    try:
        q = enforce_quotas(servers)
    except Exception as e:
        print(f'[quota] failed: {e}', file=sys.stderr)
        q = {'suspended': 0, 'resumed': 0}

    print(f'[sync] ok={len(ok)} failed={len(bad)} '
          f'| suspended={q["suspended"]} resumed={q["resumed"]}'
          + (f' | failures: {", ".join(f"{b["server"]}({b["error"]})" for b in bad)}' if bad else ''))


if __name__ == '__main__':
    main()
