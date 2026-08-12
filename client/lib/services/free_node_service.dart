import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/free_node.dart';

/// 共享节点订阅：拉取(主/备 host 依次尝试)→ base64 解码 → 解析成 sing-box outbound。
///
/// 是 vpn/free-nodes/node_parser.py 的 Dart 移植。App 直连订阅服务，不经 Supabase
/// (避免 egress 成本)。地址走非标端口 HTTPS，证书须匹配域名。
class FreeNodeService {
  static final FreeNodeService instance = FreeNodeService._();
  FreeNodeService._();

  // 订阅源(主/备,依次尝试)。以后加主机只改这里。
  static const List<String> _subHosts = [
    'https://scanner.mirrorspeed.com:10612',
    'https://msscanner.mirrorquant.com:10612',
  ];
  // 清单路径：全量 / 精选(top50)。精选路径暂用同一个,你定好后改这里。
  static const String _pathAll    = '/7385e047b29180935b3686c5/subscribe2.txt';
  static const String _pathTop    = '/7385e047b29180935b3686c5/subscribe2.txt';

  /// 拉取并解析节点。[top]=true 取精选清单。失败(全部 host 都不通)返回空列表。
  Future<List<FreeNode>> fetch({bool top = false}) async {
    final path = top ? _pathTop : _pathAll;
    String? body;
    for (final host in _subHosts) {
      try {
        final res = await http
            .get(Uri.parse('$host$path'), headers: {'User-Agent': 'MirrorSpeed'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          body = res.body;
          break;
        }
      } catch (_) {
        // 试下一个 host
      }
    }
    if (body == null) return [];
    return parseSubscription(body);
  }

  /// 诊断：逐个 host 尝试并返回可读报告（测试用）。
  Future<List<String>> diagnose({bool top = false}) async {
    final path = top ? _pathTop : _pathAll;
    final out = <String>[];
    for (final host in _subHosts) {
      final url = '$host$path';
      try {
        final sw = Stopwatch()..start();
        final res = await http
            .get(Uri.parse(url), headers: {'User-Agent': 'MirrorSpeed'})
            .timeout(const Duration(seconds: 12));
        sw.stop();
        final bytes = res.bodyBytes.length;
        if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
          final n = parseSubscription(res.body).length;
          out.add('$host → 200, ${bytes}B, ${sw.elapsedMilliseconds}ms, 解析 $n 个');
        } else {
          out.add('$host → HTTP ${res.statusCode}, ${bytes}B (非200或空)');
        }
      } catch (e) {
        out.add('$host → 异常: $e');
      }
    }
    return out;
  }

  // ── 解析 ──────────────────────────────────────────────────────────────────

  /// 整份订阅(base64 或明文多行)→ 去重后的节点列表。
  static List<FreeNode> parseSubscription(String text) {
    var s = text.trim();
    // 尝试整体 base64 解码;失败则当明文
    final decoded = _tryB64(s);
    if (decoded != null && decoded.contains('://')) s = decoded;

    final out = <FreeNode>[];
    final seen = <String>{};
    for (var line in const LineSplitter().convert(s)) {
      line = line.trim();
      if (!line.contains('://')) continue;
      final n = parseUri(line);
      if (n != null && seen.add(n.fingerprint)) out.add(n);
    }
    return out;
  }

  static FreeNode? parseUri(String uri) {
    uri = uri.trim();
    final i = uri.indexOf('://');
    if (i < 0) return null;
    final scheme = uri.substring(0, i).toLowerCase();
    try {
      switch (scheme) {
        case 'vless':      return _vless(uri);
        case 'trojan':     return _trojan(uri);
        case 'ss':         return _ss(uri);
        case 'vmess':      return _vmess(uri);
        case 'hysteria2':
        case 'hy2':        return _hysteria2(uri);
        case 'anytls':     return _anytls(uri);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  // ── helpers ─────────────────────────────────────────────────────────────
  static String? _tryB64(String s) {
    try {
      var t = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s'), '');
      t = t.padRight(t.length + ((4 - t.length % 4) % 4), '=');
      return utf8.decode(base64.decode(t), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static String _fp(String protocol, String server, int port, String secret) =>
      sha1.convert(utf8.encode('$protocol|$server|$port|$secret')).toString();

  static String _name(String frag, String def) {
    if (frag.isEmpty) return def;
    try { return Uri.decodeComponent(frag); } catch (_) { return def; }
  }

  /// 拆 userinfo@host:port?query#frag → (userinfo, host, port, query, frag)
  static _Parts _common(String uri) {
    var rest = uri.substring(uri.indexOf('://') + 3);
    final hashIdx = rest.indexOf('#');
    final frag = hashIdx >= 0 ? rest.substring(hashIdx + 1) : '';
    if (hashIdx >= 0) rest = rest.substring(0, hashIdx);
    final qIdx = rest.indexOf('?');
    final query = qIdx >= 0 ? rest.substring(qIdx + 1) : '';
    final main = qIdx >= 0 ? rest.substring(0, qIdx) : rest;
    final at = main.lastIndexOf('@');
    final userinfo = at >= 0 ? main.substring(0, at) : '';
    final hostport = at >= 0 ? main.substring(at + 1) : main;
    final colon = hostport.lastIndexOf(':');
    final host = hostport.substring(0, colon);
    final port = int.parse(hostport.substring(colon + 1));
    return _Parts(userinfo, host, port, Uri.splitQueryString(query), frag);
  }

  static Map<String, dynamic>? _transport(Map<String, String> q) {
    final net = q['type'] ?? '';
    if (net == 'ws' || net == 'httpupgrade') {
      final t = <String, dynamic>{'type': 'ws', 'path': q['path'] ?? '/'};
      final host = q['host'] ?? '';
      if (host.isNotEmpty) t['headers'] = {'Host': host};
      return t;
    }
    if (net == 'grpc') return {'type': 'grpc', 'service_name': q['serviceName'] ?? ''};
    return null;
  }

  static Map<String, dynamic> _tls(Map<String, String> q, [String defaultSni = '']) {
    final sec = q['security'] ?? '';
    final sni = q['sni'] ?? q['peer'] ?? defaultSni;
    final tls = <String, dynamic>{'enabled': true};
    if (sni.isNotEmpty) tls['server_name'] = sni;
    final fp = q['fp'] ?? '';
    if (fp.isNotEmpty) tls['utls'] = {'enabled': true, 'fingerprint': fp};
    if (sec == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': q['pbk'] ?? '',
        'short_id': q['sid'] ?? '',
      };
    }
    if (q['allowInsecure'] == '1' || q['allowInsecure'] == 'true') tls['insecure'] = true;
    return tls;
  }

  static FreeNode _vless(String uri) {
    final p = _common(uri);
    final ob = <String, dynamic>{
      'type': 'vless', 'tag': 'proxy',
      'server': p.host, 'server_port': p.port, 'uuid': p.userinfo,
    };
    final flow = p.q['flow'] ?? '';
    if (flow.isNotEmpty) ob['flow'] = flow;
    final sec = p.q['security'] ?? '';
    if (sec == 'tls' || sec == 'reality' || sec == 'xtls') ob['tls'] = _tls(p.q);
    final tr = _transport(p.q);
    if (tr != null) ob['transport'] = tr;
    return FreeNode(fingerprint: _fp('vless', p.host, p.port, p.userinfo), protocol: 'vless',
        name: _name(p.frag, 'vless'), server: p.host, port: p.port, outbound: ob);
  }

  static FreeNode _trojan(String uri) {
    final p = _common(uri);
    final ob = <String, dynamic>{
      'type': 'trojan', 'tag': 'proxy',
      'server': p.host, 'server_port': p.port,
      'password': Uri.decodeComponent(p.userinfo), 'tls': _tls(p.q),
    };
    final tr = _transport(p.q);
    if (tr != null) ob['transport'] = tr;
    return FreeNode(fingerprint: _fp('trojan', p.host, p.port, p.userinfo), protocol: 'trojan',
        name: _name(p.frag, 'trojan'), server: p.host, port: p.port, outbound: ob);
  }

  static FreeNode _ss(String uri) {
    var rest = uri.substring(uri.indexOf('://') + 3);
    final hashIdx = rest.indexOf('#');
    final frag = hashIdx >= 0 ? rest.substring(hashIdx + 1) : '';
    if (hashIdx >= 0) rest = rest.substring(0, hashIdx);
    final main = rest.split('?').first;
    String method, password, host; int port;
    if (main.contains('@')) {
      final at = main.lastIndexOf('@');
      final ui = main.substring(0, at);
      final dec = _tryB64(ui) ?? Uri.decodeComponent(ui);
      final ci = dec.indexOf(':');
      method = dec.substring(0, ci); password = dec.substring(ci + 1);
      final hp = main.substring(at + 1); final c = hp.lastIndexOf(':');
      host = hp.substring(0, c); port = int.parse(hp.substring(c + 1));
    } else {
      final dec = _tryB64(main)!;
      final at = dec.lastIndexOf('@');
      final cred = dec.substring(0, at); final hp = dec.substring(at + 1);
      final ci = cred.indexOf(':');
      method = cred.substring(0, ci); password = cred.substring(ci + 1);
      final c = hp.lastIndexOf(':'); host = hp.substring(0, c); port = int.parse(hp.substring(c + 1));
    }
    final ob = <String, dynamic>{
      'type': 'shadowsocks', 'tag': 'proxy',
      'server': host, 'server_port': port, 'method': method, 'password': password,
    };
    return FreeNode(fingerprint: _fp('ss', host, port, password), protocol: 'ss',
        name: _name(frag, 'ss'), server: host, port: port, outbound: ob);
  }

  static FreeNode _vmess(String uri) {
    final raw = uri.substring(uri.indexOf('://') + 3);
    final cfg = jsonDecode(_tryB64(raw)!) as Map<String, dynamic>;
    final host = cfg['add'].toString();
    final port = int.parse(cfg['port'].toString());
    final uuid = cfg['id'].toString();
    final ob = <String, dynamic>{
      'type': 'vmess', 'tag': 'proxy',
      'server': host, 'server_port': port, 'uuid': uuid,
      'security': cfg['scy'] ?? 'auto',
      'alter_id': int.tryParse('${cfg['aid'] ?? 0}') ?? 0,
    };
    if (cfg['tls'] == 'tls') {
      ob['tls'] = {'enabled': true, 'server_name': cfg['sni'] ?? cfg['host'] ?? host};
    }
    final net = cfg['net'] ?? 'tcp';
    if (net == 'ws') {
      final t = <String, dynamic>{'type': 'ws', 'path': cfg['path'] ?? '/'};
      if ((cfg['host'] ?? '').toString().isNotEmpty) t['headers'] = {'Host': cfg['host']};
      ob['transport'] = t;
    } else if (net == 'grpc') {
      ob['transport'] = {'type': 'grpc', 'service_name': cfg['path'] ?? ''};
    }
    return FreeNode(fingerprint: _fp('vmess', host, port, uuid), protocol: 'vmess',
        name: _name('${cfg['ps'] ?? ''}', 'vmess'), server: host, port: port, outbound: ob);
  }

  static FreeNode _hysteria2(String uri) {
    final p = _common(uri);
    final ob = <String, dynamic>{
      'type': 'hysteria2', 'tag': 'proxy',
      'server': p.host, 'server_port': p.port,
      'password': Uri.decodeComponent(p.userinfo), 'tls': _tls(p.q),
    };
    return FreeNode(fingerprint: _fp('hysteria2', p.host, p.port, p.userinfo), protocol: 'hysteria2',
        name: _name(p.frag, 'hysteria2'), server: p.host, port: p.port, outbound: ob);
  }

  static FreeNode _anytls(String uri) {
    final p = _common(uri);
    final ob = <String, dynamic>{
      'type': 'anytls', 'tag': 'proxy',
      'server': p.host, 'server_port': p.port,
      'password': Uri.decodeComponent(p.userinfo), 'tls': _tls(p.q),
    };
    return FreeNode(fingerprint: _fp('anytls', p.host, p.port, p.userinfo), protocol: 'anytls',
        name: _name(p.frag, 'anytls'), server: p.host, port: p.port, outbound: ob);
  }
}

class _Parts {
  final String userinfo, host, frag;
  final int port;
  final Map<String, String> q;
  _Parts(this.userinfo, this.host, this.port, this.q, this.frag);
}
