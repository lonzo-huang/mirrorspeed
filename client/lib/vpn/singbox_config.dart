import 'dart:convert';
import '../models/free_node.dart';

/// 把单个免费节点的 outbound 组装成一份完整、可直接交给 sing-box(libbox)运行的
/// 配置 JSON。含 tun 入站 + 路由规则 + DNS。
///
/// 参数：
///   [node]        选中的共享节点(其 outbound 会被标 tag=proxy)
///   [smart]       true=智能分流(中国大陆/局域网直连,其余走代理);false=全局
///   [cnRuleSet]   中国 IP 规则集(智能分流用;为空则退化为仅按 geoip=cn 直连)
///   [adOnly]      true=广告受限隧道:只放行 Google 广告域名走代理,其余直连
class SingboxConfig {
  static const List<String> _adDomains = [
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'googletagservices.com',
    'admob.com',
    'gstatic.com',    // 广告 SDK 资源
  ];

  static Map<String, dynamic> build(
    FreeNode node, {
    bool smart = true,
    bool adOnly = false,
    String? logPath,   // 非空则把 sing-box 日志(debug)写到该文件，供诊断
  }) {
    // 选中节点的 outbound(强制 tag=proxy)
    final proxy = Map<String, dynamic>.from(node.outbound)..['tag'] = 'proxy';

    final route = <String, dynamic>{
      'auto_detect_interface': true,
      // 节点服务器域名用本地直连 DNS 解析(bootstrap)，避免"要连节点先解析域名、
      // 解析域名又要先连上节点"的死锁。
      'default_domain_resolver': 'local',
      'final': adOnly ? 'direct' : 'proxy',
      'rules': <Map<String, dynamic>>[
        // 域名嗅探(sing-box 1.12+ 用 route action，不再放 inbound)
        {'action': 'sniff'},
        // DNS 劫持(1.13 起 dns outbound 已移除，改用 hijack-dns action)
        {'protocol': 'dns', 'action': 'hijack-dns'},
        // 局域网 / 私有地址直连
        {'ip_is_private': true, 'outbound': 'direct'},
      ],
    };

    if (adOnly) {
      // 广告模式:只有广告域名走代理,其余全直连
      route['rules'].add({
        'domain_suffix': _adDomains,
        'outbound': 'proxy',
      });
      route['final'] = 'direct';
    } else if (smart) {
      // 智能模式:中国大陆 geoip 直连,其余走代理(final=proxy)
      route['rules'].add({'geoip': ['cn', 'private'], 'outbound': 'direct'});
      route['final'] = 'proxy';
    }
    // 全局模式:除上面的 dns/私网规则外,final=proxy 全走代理

    return {
      'log': logPath != null
          ? {'level': 'debug', 'output': logPath, 'timestamp': true}
          : {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          // 代理侧解析(防污染)：主 Cloudflare DoH + 权威 Google DoH 兜底
          {'tag': 'remote',      'address': 'https://1.1.1.1/dns-query', 'detour': 'proxy'},
          {'tag': 'remote_auth', 'address': 'https://8.8.8.8/dns-query', 'detour': 'proxy'},
          // 直连侧：本地公共 DNS + 系统 DNS 兜底(解析节点域名/直连域名)
          {'tag': 'local',  'address': '223.5.5.5', 'detour': 'direct'},
          {'tag': 'system', 'address': 'local',     'detour': 'direct'},
        ],
        'rules': [
          if (smart && !adOnly) {'geoip': 'cn', 'server': 'local'},
        ],
        'final': adOnly ? 'local' : 'remote',
        'strategy': 'ipv4_only',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'mirrorspeed-sb',
          // 1.13：inet4_address 已改名 address(列表)
          'address': ['172.19.0.1/30'],
          'auto_route': true,
          'strict_route': false,
          'stack': 'gvisor',
        },
      ],
      'outbounds': [
        proxy,
        {'type': 'direct', 'tag': 'direct'},
        // dns outbound 已在 1.13 移除，DNS 劫持改由 route action hijack-dns 处理
      ],
      'route': route,
    };
  }

  /// 便捷:直接产出配置的 JSON 字符串(交给原生 libbox)。
  static String buildJson(FreeNode node, {bool smart = true, bool adOnly = false}) =>
      jsonEncode(build(node, smart: smart, adOnly: adOnly));
}
