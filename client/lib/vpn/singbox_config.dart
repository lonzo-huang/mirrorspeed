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
    List<String>? includePackages,   // 分应用(Android)：只有这些 App 进隧道(白名单)
    List<String>? excludePackages,   // 分应用(Android)：这些 App 绕过隧道(黑名单)
    List<String>? includeProcesses,  // 分应用(桌面)：只有这些进程走代理(白名单，process_name)
    List<String>? excludeProcesses,  // 分应用(桌面)：这些进程直连(黑名单，process_name)
  }) {
    // 选中节点的 outbound(强制 tag=proxy)
    final proxy = Map<String, dynamic>.from(node.outbound)..['tag'] = 'proxy';

    final hasWhiteProc = includeProcesses != null && includeProcesses.isNotEmpty;
    final hasBlackProc = excludeProcesses != null && excludeProcesses.isNotEmpty;

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

    // 桌面分应用(process_name)：黑名单进程直连，放在最前，优先于地区/最终规则。
    if (hasBlackProc) {
      route['rules'].add({'process_name': excludeProcesses, 'outbound': 'direct'});
    }

    if (adOnly) {
      // 广告模式:只有广告域名走代理,其余全直连
      route['rules'].add({
        'domain_suffix': _adDomains,
        'outbound': 'proxy',
      });
      route['final'] = 'direct';
    } else if (hasWhiteProc) {
      // 桌面白名单：仅名单内进程走代理，其余一律直连（覆盖 smart/global 的 final）。
      route['rules'].add({'process_name': includeProcesses, 'outbound': 'proxy'});
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
          // 代理侧解析：用 TCP plain DNS(而非 DoH)——坏节点常对 DoH 回 403/证书错，
          // TCP DNS 只需代理能转发 TCP，皮实很多。主 Cloudflare + 权威 Google 兜底。
          {'tag': 'remote',      'address': 'tcp://1.1.1.1', 'detour': 'proxy'},
          {'tag': 'remote_auth', 'address': 'tcp://8.8.8.8', 'detour': 'proxy'},
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
          // 分应用：白名单只放这些 App 进隧道；黑名单让这些 App 绕过。
          if (includePackages != null && includePackages.isNotEmpty)
            'include_package': includePackages,
          if (excludePackages != null && excludePackages.isNotEmpty)
            'exclude_package': excludePackages,
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
