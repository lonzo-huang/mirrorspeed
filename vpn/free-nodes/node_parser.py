"""
node_parser.py — 把机场订阅里的节点 URI 解析成 sing-box outbound JSON。

支持:vless / trojan / shadowsocks(ss) / vmess / hysteria2 / anytls
输出结构与 airportscanner 的 build_singbox_config 对齐,端上拿到直接塞进
sing-box 配置的 outbounds,无需再解析。

纯标准库。每条返回 dict：{fingerprint, protocol, name, server, port, outbound}
无法解析 / 不支持 → 返回 None(调用方过滤)。
"""

import base64
import hashlib
import json
import urllib.parse
from typing import Optional


def _b64pad(s: str) -> bytes:
    s = s.strip().replace('-', '+').replace('_', '/')
    return base64.b64decode(s + '=' * (-len(s) % 4))


def _fp(protocol: str, server: str, port, secret: str) -> str:
    return hashlib.sha1(f'{protocol}|{server}|{port}|{secret}'.encode()).hexdigest()


def _name(frag: str, default: str) -> str:
    if not frag:
        return default
    try:
        return urllib.parse.unquote(frag)
    except Exception:
        return default


def _transport(q: dict) -> Optional[dict]:
    """ws / grpc / http 传输;raw/tcp/未指定 → None(sing-box 默认 tcp)。"""
    net = (q.get('type') or [''])[0]
    if net in ('ws', 'httpupgrade'):
        t = {'type': 'ws', 'path': (q.get('path') or ['/'])[0]}
        host = (q.get('host') or [''])[0]
        if host:
            t['headers'] = {'Host': host}
        return t
    if net == 'grpc':
        return {'type': 'grpc', 'service_name': (q.get('serviceName') or [''])[0]}
    return None


def _tls(q: dict, default_sni: str = '') -> dict:
    sec = (q.get('security') or [''])[0]
    sni = (q.get('sni') or q.get('peer') or [default_sni])[0]
    tls: dict = {'enabled': True}
    if sni:
        tls['server_name'] = sni
    fp = (q.get('fp') or [''])[0]
    if fp:
        tls['utls'] = {'enabled': True, 'fingerprint': fp}
    if sec == 'reality':
        tls['reality'] = {
            'enabled':    True,
            'public_key': (q.get('pbk') or [''])[0],
            'short_id':   (q.get('sid') or [''])[0],
        }
    if (q.get('allowInsecure') or ['0'])[0] in ('1', 'true'):
        tls['insecure'] = True
    return tls


def parse(uri: str) -> Optional[dict]:
    uri = uri.strip()
    if '://' not in uri:
        return None
    scheme = uri.split('://', 1)[0].lower()
    try:
        if scheme == 'vless':
            return _vless(uri)
        if scheme == 'trojan':
            return _trojan(uri)
        if scheme == 'ss':
            return _ss(uri)
        if scheme == 'vmess':
            return _vmess(uri)
        if scheme in ('hysteria2', 'hy2'):
            return _hysteria2(uri)
        if scheme == 'anytls':
            return _anytls(uri)
    except Exception:
        return None
    return None


def _common(uri: str):
    """拆出 uuid@host:port?query#frag。"""
    body, _, frag = uri.split('://', 1)[1].partition('#')
    main, _, query = body.partition('?')
    userinfo, _, hostport = main.rpartition('@')
    host, _, port = hostport.rpartition(':')
    q = urllib.parse.parse_qs(query)
    return userinfo, host, int(port), q, frag


def _vless(uri: str) -> Optional[dict]:
    uuid, host, port, q, frag = _common(uri)
    ob = {
        'type': 'vless', 'tag': 'proxy',
        'server': host, 'server_port': port,
        'uuid': uuid,
    }
    flow = (q.get('flow') or [''])[0]
    if flow:
        ob['flow'] = flow
    sec = (q.get('security') or [''])[0]
    if sec in ('tls', 'reality', 'xtls'):
        ob['tls'] = _tls(q)
    tr = _transport(q)
    if tr:
        ob['transport'] = tr
    return {'fingerprint': _fp('vless', host, port, uuid), 'protocol': 'vless',
            'name': _name(frag, 'vless'), 'server': host, 'port': port, 'outbound': ob}


def _trojan(uri: str) -> Optional[dict]:
    pw, host, port, q, frag = _common(uri)
    ob = {
        'type': 'trojan', 'tag': 'proxy',
        'server': host, 'server_port': port,
        'password': urllib.parse.unquote(pw),
        'tls': _tls(q),
    }
    tr = _transport(q)
    if tr:
        ob['transport'] = tr
    return {'fingerprint': _fp('trojan', host, port, pw), 'protocol': 'trojan',
            'name': _name(frag, 'trojan'), 'server': host, 'port': port, 'outbound': ob}


def _ss(uri: str) -> Optional[dict]:
    # 两种形态：ss://base64(method:pass)@host:port  或  ss://base64(method:pass@host:port)
    body, _, frag = uri.split('://', 1)[1].partition('#')
    main = body.split('?', 1)[0]
    if '@' in main:
        userinfo, _, hostport = main.rpartition('@')
        try:
            dec = _b64pad(userinfo).decode()
        except Exception:
            dec = urllib.parse.unquote(userinfo)
        method, _, password = dec.partition(':')
        host, _, port = hostport.rpartition(':')
    else:
        dec = _b64pad(main).decode()
        cred, _, hostport = dec.rpartition('@')
        method, _, password = cred.partition(':')
        host, _, port = hostport.rpartition(':')
    port = int(port)
    ob = {'type': 'shadowsocks', 'tag': 'proxy', 'server': host, 'server_port': port,
          'method': method, 'password': password}
    return {'fingerprint': _fp('ss', host, port, password), 'protocol': 'ss',
            'name': _name(frag, 'ss'), 'server': host, 'port': port, 'outbound': ob}


def _vmess(uri: str) -> Optional[dict]:
    raw = uri.split('://', 1)[1]
    cfg = json.loads(_b64pad(raw).decode())
    host = cfg['add']
    port = int(cfg['port'])
    uuid = cfg['id']
    ob = {
        'type': 'vmess', 'tag': 'proxy',
        'server': host, 'server_port': port,
        'uuid': uuid, 'security': cfg.get('scy', 'auto'),
        'alter_id': int(cfg.get('aid', 0) or 0),
    }
    if cfg.get('tls') == 'tls':
        ob['tls'] = {'enabled': True, 'server_name': cfg.get('sni') or cfg.get('host') or host}
    net = cfg.get('net', 'tcp')
    if net == 'ws':
        t = {'type': 'ws', 'path': cfg.get('path') or '/'}
        if cfg.get('host'):
            t['headers'] = {'Host': cfg['host']}
        ob['transport'] = t
    elif net == 'grpc':
        ob['transport'] = {'type': 'grpc', 'service_name': cfg.get('path') or ''}
    return {'fingerprint': _fp('vmess', host, port, uuid), 'protocol': 'vmess',
            'name': _name(cfg.get('ps', ''), 'vmess'), 'server': host, 'port': port, 'outbound': ob}


def _hysteria2(uri: str) -> Optional[dict]:
    pw, host, port, q, frag = _common(uri)
    ob = {
        'type': 'hysteria2', 'tag': 'proxy',
        'server': host, 'server_port': port,
        'password': urllib.parse.unquote(pw),
        'tls': _tls(q),
    }
    return {'fingerprint': _fp('hysteria2', host, port, pw), 'protocol': 'hysteria2',
            'name': _name(frag, 'hysteria2'), 'server': host, 'port': port, 'outbound': ob}


def _anytls(uri: str) -> Optional[dict]:
    pw, host, port, q, frag = _common(uri)
    ob = {
        'type': 'anytls', 'tag': 'proxy',
        'server': host, 'server_port': port,
        'password': urllib.parse.unquote(pw),
        'tls': _tls(q),
    }
    return {'fingerprint': _fp('anytls', host, port, pw), 'protocol': 'anytls',
            'name': _name(frag, 'anytls'), 'server': host, 'port': port, 'outbound': ob}


def parse_subscription(text: str) -> list:
    """整份订阅(可能是 base64 或明文多行)→ 解析出的节点列表(已去 None)。"""
    body = text.strip()
    # 尝试整体 base64 解码;失败则当明文
    try:
        decoded = _b64pad(body).decode('utf-8', 'ignore')
        if '://' in decoded:
            body = decoded
    except Exception:
        pass
    out, seen = [], set()
    for line in body.splitlines():
        line = line.strip()
        if '://' not in line:
            continue
        node = parse(line)
        if node and node['fingerprint'] not in seen:
            seen.add(node['fingerprint'])
            out.append(node)
    return out
