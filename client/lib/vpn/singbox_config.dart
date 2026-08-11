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
  }) {
    // 选中节点的 outbound(强制 tag=proxy)
    final proxy = Map<String, dynamic>.from(node.outbound)..['tag'] = 'proxy';

    final route = <String, dynamic>{
      'auto_detect_interface': true,
      'final': adOnly ? 'direct' : (smart ? 'proxy' : 'proxy'),
      'rules': <Map<String, dynamic>>[
        // DNS 劫持到 sing-box 的 DNS
        {'protocol': 'dns', 'outbound': 'dns-out'},
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
      'log': {'level': 'warn', 'timestamp': true},
      'dns': {
        'servers': [
          {'tag': 'remote', 'address': 'https://1.1.1.1/dns-query', 'detour': 'proxy'},
          {'tag': 'local',  'address': '223.5.5.5', 'detour': 'direct'},
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
          'inet4_address': '172.19.0.1/30',
          'auto_route': true,
          'strict_route': false,
          'stack': 'gvisor',
          'sniff': true,          // 嗅探域名(域名规则分流的前提)
          'sniff_override_destination': false,
        },
      ],
      'outbounds': [
        proxy,
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': route,
    };
  }

  /// 便捷:直接产出配置的 JSON 字符串(交给原生 libbox)。
  static String buildJson(FreeNode node, {bool smart = true, bool adOnly = false}) =>
      jsonEncode(build(node, smart: smart, adOnly: adOnly));
}
