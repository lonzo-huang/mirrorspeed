import 'dart:convert';
import 'dart:io' show Platform;
import '../models/free_node.dart';

/// 桌面(Windows/macOS)：sing-box.exe 自管 tun，需要 strict_route 堵漏。
final bool _kIsDesktop = Platform.isWindows || Platform.isMacOS;

/// Apple（iOS/macOS）：智能分流用 sing-box 的 rule_set 能力（geoip-cn + geosite-cn），
/// 规则集随隧道扩展打包，路径占位符 `$RULESET_DIR` 由扩展换成真实 bundle 路径。
/// 其它平台维持原状（Windows/安卓的免费节点仍是全局隧道，行为不变）。
final bool _kIsApple = Platform.isIOS || Platform.isMacOS;
const String _kRuleSetDir = r'$RULESET_DIR';

/// 把单个免费节点的 outbound 组装成一份完整、可直接交给 sing-box(libbox)运行的
/// 配置 JSON。含 tun 入站 + 路由规则 + DNS。
///
/// 参数：
///   [outbound]    选中节点的 sing-box outbound(会被标 tag=proxy)。免费节点来自
///                 订阅解析，优质节点来自 /api/mobile/configs 的 singbox 块 ——
///                 两者在这一层没有区别，所以共用同一套路由/DNS/分应用逻辑。
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
    Map<String, dynamic> outbound, {
    bool smart = true,
    bool adOnly = false,
    String? logPath,   // 非空则把 sing-box 日志(debug)写到该文件，供诊断
    List<String>? includePackages,   // 分应用(Android)：只有这些 App 进隧道(白名单)
    List<String>? excludePackages,   // 分应用(Android)：这些 App 绕过隧道(黑名单)
    List<String>? includeProcesses,  // 分应用(桌面)：只有这些进程走代理(白名单，process_name)
    List<String>? excludeProcesses,  // 分应用(桌面)：这些进程直连(黑名单，process_name)
    List<String>? cnCidrs,           // 回退：中国 IP 段(assets/routes/cn_cidr.txt)，仅 IP 级
    String? cnRuleSetPath,           // 首选：airlane-cn.srs 的本地绝对路径(域名+IP 级)；非 Apple 由调用方释放后传入
    bool ipv6 = false,               // 仅当系统确有可用 IPv6 时给 tun 加 v6 地址（见下）
  }) {
    // 选中节点的 outbound(强制 tag=proxy)
    final proxy = Map<String, dynamic>.from(outbound)..['tag'] = 'proxy';

    // airlane-cn 规则集(域名+IP 级 CN 直连，三端统一)：Apple 走扩展占位符，其它平台用调用方
    // 释放到磁盘后传入的绝对路径；两者都没有则回退 cnCidrs(ip_cidr，仅 IP 级)。
    final String? cnRsPath = _kIsApple ? '$_kRuleSetDir/airlane-cn.srs' : cnRuleSetPath;
    final bool useCnRuleSet = cnRsPath != null && cnRsPath.isNotEmpty;

    final hasWhiteProc = includeProcesses != null && includeProcesses.isNotEmpty;
    final hasBlackProc = excludeProcesses != null && excludeProcesses.isNotEmpty;

    final route = <String, dynamic>{
      'auto_detect_interface': true,
      // 节点服务器域名用【local=223.5.5.5 直连】解析(bootstrap)，避免"要连节点先解析域名、
      // 解析域名又要先连上节点"的死锁。
      // 【切勿用 'system'】sing-box 的 system/address:'local' 在安卓 libbox 上会去查
      // 127.0.0.1:53 / [::1]:53(无人监听)→ connection refused → 节点域名永远解析不了 →
      // 代理拨不通 → "已连接却上不了网"。223.5.5.5 全球可达(境外略慢但必成)。
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

    // 广告域名始终走代理：即便处于白名单/黑名单/智能直连，也不让 App 自身的广告请求
    // 走直连——国内直连 AdMob/Google 被墙会导致广告加载不出。放在分应用/地区规则之前，
    // 优先级最高。（adOnly 模式本就只代理广告域名，不重复加。）
    if (!adOnly) {
      route['rules'].add({'domain_suffix': _adDomains, 'outbound': 'proxy'});
    }

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
    } else if (smart && useCnRuleSet) {
      // 智能模式：airlane-cn 规则集(域名+IP 级)直连国内，其余走代理。三端统一。
      route['rules'].add({'rule_set': ['airlane-cn'], 'outbound': 'direct'});
      route['final'] = 'proxy';
    } else if (smart) {
      // 回退：拿不到 airlane-cn 路径(释放失败)时，用本地 cn_cidr 列表(ip_cidr，仅 IP 级)直连。
      if (cnCidrs != null && cnCidrs.isNotEmpty) {
        route['rules'].add({'ip_cidr': cnCidrs, 'outbound': 'direct'});
      }
      route['final'] = 'proxy';
    }
    // 全局模式:除上面的 dns/私网规则外,final=proxy 全走代理

    // 本地规则集声明（智能模式且拿到 airlane-cn 路径时；其它情况不写，避免多余文件依赖）。
    if (smart && useCnRuleSet && !adOnly && !hasWhiteProc) {
      route['rule_set'] = [
        {'type': 'local', 'tag': 'airlane-cn', 'format': 'binary', 'path': cnRsPath},
      ];
    }

    return {
      'log': logPath != null
          ? {'level': 'debug', 'output': logPath, 'timestamp': true}
          : {'level': 'warn', 'timestamp': true},
      // clash_api：仅为启用流量统计跟踪器(command server 的 StatusMessage 上下行字节靠它;
      //   不开它 trafficAvailable=false、速率恒 0)。不设 external_controller=不监听任何端口。
      // cache_file：持久化 DNS/fakeip 缓存到 work 目录,切换节点(reload)后 DNS 不清空 → 平滑。
      'experimental': {
        'clash_api': <String, dynamic>{},
        'cache_file': {'enabled': true, 'path': 'cache.db', 'store_fakeip': false},
      },
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
          // 智能模式且有 airlane-cn 规则集时，国内域名走本地 DNS 解析（避免经代理 DNS 绕路）。
          // 回退(无 rule_set)时不加此规则，国内域名经代理 DNS 解析(略慢但可用)。
          if (smart && !adOnly && useCnRuleSet) {'rule_set': 'airlane-cn', 'server': 'local'},
        ],
        'final': adOnly ? 'local' : 'remote',
        'strategy': 'ipv4_only',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'interface_name': 'mirrorspeed-sb',
          // 1.13：inet4_address 已改名 address(列表)。
          // IPv6：仅当系统确有可用 IPv6 时才给 tun 加 v6 地址，让 auto_route 也张 ::/0、
          // 堵住 IPv6 泄漏（双栈网络下 IPv6 流量会绕过隧道）。但在 **IPv6 被禁用** 的机器上
          // （很多企业 Windows），sing-box 设 v6 地址会 FATAL「set ipv6 address: Element not
          // found」→ 整个隧道起不来。故由上层探测后用 [ipv6] 控制，无 v6 环境退回纯 IPv4。
          'address': ipv6 ? ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'] : ['172.19.0.1/30'],
          'auto_route': true,
          // 桌面(Windows)开 strict_route：强制所有流量进隧道、堵住泄漏。
          'strict_route': _kIsDesktop,
          // TUN 协议栈：安卓用 system(内核栈)——启动更快、吞吐更高，解决"点连接后 4-5 秒
          // 才起隧道"的卡顿；gvisor(用户态栈)启动重。Apple/桌面保持 gvisor(更稳，可回退)。
          'stack': Platform.isAndroid ? 'system' : 'gvisor',
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
      jsonEncode(build(node.outbound, smart: smart, adOnly: adOnly));
}
