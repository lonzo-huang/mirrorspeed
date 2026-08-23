import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import '../models/free_node.dart';

/// 共享节点订阅：拉取(主/备 host 依次尝试)→ base64 解码 → 解析成 sing-box outbound。
///
/// 是 vpn/free-nodes/node_parser.py 的 Dart 移植。App 直连订阅服务，不经 Supabase
/// (避免 egress 成本)。地址走非标端口 HTTPS，证书须匹配域名。
class FreeNodeService {
  static final FreeNodeService instance = FreeNodeService._();
  FreeNodeService._();

  // 订阅源(主/备,依次尝试)。以后加主机只改这里。
  // 主：原生 http:10611（通用可达）。备：https:10612（部分网络端口被挡/证书问题）。
  // http 明文已在 network_security_config.xml 对该域名单独放行。
  static const List<String> _subHosts = [
    'http://scanner.mirrorspeed.com:10611',
    'https://scanner.mirrorspeed.com:10612',
  ];
  // 清单路径：全量(base64 URI 列表) / 精选(Clash YAML，扫描程序做过健康检查的 top50)。
  static const String _pathAll    = '/7385e047b29180935b3686c5/subscribe2.txt';
  static const String _pathTop    = '/7385e047b29180935b3686c5/clash_top50.yaml';

  /// 拉取并解析节点。[top]=true 取精选清单。失败(全部 host 都不通)返回空列表。
  Future<List<FreeNode>> fetch({bool top = false}) async {
    final path = top ? _pathTop : _pathAll;
    String? body;
    for (final host in _subHosts) {
      try {
        final res = await http
            .get(Uri.parse('$host$path'), headers: {'User-Agent': 'MirrorSpeed'})
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          // 显式 UTF-8 解码：http 默认 latin1，会把 emoji/中文变乱码。
          body = utf8.decode(res.bodyBytes, allowMalformed: true);
          if (body.trim().isEmpty) { body = null; continue; }
          break;
        }
      } catch (_) {
        // 试下一个 host
      }
    }
    if (body == null) return [];
    return _parseAny(body);
  }

  /// 按内容嗅探：Clash YAML(以 proxies: 开头) → parseClashYaml；否则当 base64/明文订阅。
  static List<FreeNode> _parseAny(String body) {
    final t = body.trimLeft();
    if (t.startsWith('proxies:') || t.contains('\nproxies:')) {
      return parseClashYaml(body);
    }
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
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          final n = _parseAny(utf8.decode(res.bodyBytes, allowMalformed: true)).length;
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

  // ── Clash YAML(精选清单 clash_top50.yaml)────────────────────────────────
  /// 解析 Clash 配置的 proxies 列表 → sing-box outbound。支持 ss/vmess/vless/trojan/
  /// hysteria2；含 tls/reality/utls 与 ws/grpc transport。不支持的类型跳过。
  static List<FreeNode> parseClashYaml(String text) {
    // 快路径：整体解析(先把 name: 值安全加引号，避免个别未加引号的特殊字符名把整份
    // 文档解析搞挂)。
    final out = <FreeNode>[];
    final seen = <String>{};
    try {
      final doc = loadYaml(_quoteNames(text));
      final proxies = (doc is Map) ? doc['proxies'] : null;
      if (proxies is List) {
        for (final p in proxies) {
          if (p is! Map) continue;
          final n = _fromClash(_deepMap(p));
          if (n != null && seen.add(n.fingerprint)) out.add(n);
        }
      }
    } catch (_) { /* 落到宽松逐项解析 */ }
    if (out.isNotEmpty) return out;
    // 兜底：逐个节点独立解析，坏节点只丢自己。
    return _parseClashLenient(text);
  }

  /// 把每行 `name: xxx` 的值强制单引号包裹(已带引号则跳过)，防止 emoji/特殊字符
  /// 未加引号导致 YAML 解析失败。
  static String _quoteNames(String text) {
    final re = RegExp(r'^(\s*(?:-\s+)?name:\s*)(\S.*?)\s*$');
    return text.split('\n').map((line) {
      final m = re.firstMatch(line);
      if (m == null) return line;
      final v = m.group(2)!;
      if ((v.startsWith("'") && v.endsWith("'")) ||
          (v.startsWith('"') && v.endsWith('"'))) return line;
      return "${m.group(1)}'${v.replaceAll("'", "''")}'";
    }).join('\n');
  }

  /// 宽松解析：抽出 proxies 块，按 `- ` 边界切成单个节点，逐个 loadYaml，坏的跳过。
  static List<FreeNode> _parseClashLenient(String text) {
    final out = <FreeNode>[];
    final seen = <String>{};
    final lines = text.split('\n');
    var i = 0;
    while (i < lines.length && lines[i].trimRight() != 'proxies:') i++;
    i++;
    final buf = <String>[];
    void flush() {
      if (buf.isEmpty) return;
      try {
        final y = loadYaml(_quoteNames(buf.join('\n')));
        if (y is Map) {
          final n = _fromClash(_deepMap(y));
          if (n != null && seen.add(n.fingerprint)) out.add(n);
        }
      } catch (_) {}
      buf.clear();
    }
    for (; i < lines.length; i++) {
      final line = lines[i];
      // 下一个顶层键(proxy-groups:/rules: 等)→ proxies 块结束
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('-')) break;
      if (line.startsWith('- ')) { flush(); buf.add(line.substring(2)); }
      else if (line.startsWith('  ')) buf.add(line.substring(2));
      else if (line.trim().isEmpty) buf.add('');
    }
    flush();
    return out;
  }

  /// YamlMap/YamlList → 普通 Dart Map/List(可 jsonEncode)。
  static dynamic _deep(dynamic v) {
    if (v is Map) return {for (final e in v.entries) e.key.toString(): _deep(e.value)};
    if (v is List) return v.map(_deep).toList();
    return v;
  }
  static Map<String, dynamic> _deepMap(Map m) => Map<String, dynamic>.from(_deep(m) as Map);

  static FreeNode? _fromClash(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString().toLowerCase();
    final server = (m['server'] ?? '').toString();
    final port = int.tryParse('${m['port']}') ?? 0;
    if (server.isEmpty || port == 0) return null;
    final name = (m['name'] ?? type).toString();
    Map<String, dynamic>? ob;
    switch (type) {
      case 'ss':
      case 'shadowsocks':
        ob = {
          'type': 'shadowsocks', 'tag': 'proxy', 'server': server, 'server_port': port,
          'method': (m['cipher'] ?? '').toString(), 'password': (m['password'] ?? '').toString(),
        };
        break;
      case 'vmess':
        ob = {
          'type': 'vmess', 'tag': 'proxy', 'server': server, 'server_port': port,
          'uuid': (m['uuid'] ?? '').toString(),
          'security': (m['cipher'] ?? 'auto').toString(),
          'alter_id': int.tryParse('${m['alterId'] ?? 0}') ?? 0,
        };
        _clashTls(ob, m);
        _clashTransport(ob, m);
        break;
      case 'vless':
        ob = {
          'type': 'vless', 'tag': 'proxy', 'server': server, 'server_port': port,
          'uuid': (m['uuid'] ?? '').toString(),
        };
        final flow = (m['flow'] ?? '').toString();
        if (flow.isNotEmpty) ob['flow'] = flow;
        _clashTls(ob, m);
        _clashTransport(ob, m);
        break;
      case 'trojan':
        ob = {
          'type': 'trojan', 'tag': 'proxy', 'server': server, 'server_port': port,
          'password': (m['password'] ?? '').toString(),
        };
        _clashTls(ob, m, forceTls: true);
        _clashTransport(ob, m);
        break;
      case 'hysteria2':
      case 'hy2':
        ob = {
          'type': 'hysteria2', 'tag': 'proxy', 'server': server, 'server_port': port,
          'password': (m['password'] ?? '').toString(),
        };
        _clashTls(ob, m, forceTls: true);
        break;
      default:
        return null; // 不支持的协议(如 ssr/tuic/wireguard)跳过
    }
    final secret = (m['uuid'] ?? m['password'] ?? '').toString();
    return FreeNode(
      fingerprint: _fp(type, server, port, secret), protocol: type,
      name: name, server: server, port: port, outbound: ob,
    );
  }

  static void _clashTls(Map<String, dynamic> ob, Map<String, dynamic> m, {bool forceTls = false}) {
    final reality = m['reality-opts'];
    final on = forceTls || m['tls'] == true || m['tls'] == 'true' || reality is Map;
    if (!on) return;
    final tls = <String, dynamic>{'enabled': true};
    final sni = (m['servername'] ?? m['sni'] ?? '').toString();
    if (sni.isNotEmpty) tls['server_name'] = sni;
    final fp = (m['client-fingerprint'] ?? '').toString();
    if (fp.isNotEmpty) tls['utls'] = {'enabled': true, 'fingerprint': fp};
    if (reality is Map) {
      tls['reality'] = {
        'enabled': true,
        'public_key': (reality['public-key'] ?? '').toString(),
        'short_id': (reality['short-id'] ?? '').toString(),
      };
    }
    if (m['skip-cert-verify'] == true) tls['insecure'] = true;
    ob['tls'] = tls;
  }

  static void _clashTransport(Map<String, dynamic> ob, Map<String, dynamic> m) {
    final net = (m['network'] ?? '').toString();
    if (net == 'ws') {
      final t = <String, dynamic>{'type': 'ws', 'path': '/'};
      final w = m['ws-opts'];
      if (w is Map) {
        if (w['path'] != null) t['path'] = w['path'].toString();
        final h = w['headers'];
        if (h is Map && h['Host'] != null) t['headers'] = {'Host': h['Host'].toString()};
      }
      ob['transport'] = t;
    } else if (net == 'grpc') {
      final g = m['grpc-opts'];
      final sn = (g is Map ? (g['grpc-service-name'] ?? '') : '').toString();
      ob['transport'] = {'type': 'grpc', 'service_name': sn};
    }
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
