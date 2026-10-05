import 'package:shared_preferences/shared_preferences.dart';
import '../services/free_node_service.dart';

/// DNS / 分流「地区方案」(第一期):
/// - auto     ：按当前网络环境自动选（境外→海外方案；境内/未知→中国大陆方案）
/// - china    ：强制中国大陆方案（airlane-cn 规则集：国内直连 + 防污染 DNS）
/// - overseas ：强制海外方案（无 GFW，不做 geo-cn 分流，全部经节点，DNS 从简）
enum DnsRegion { auto, china, overseas }

class DnsRegionStore {
  DnsRegionStore._();
  static const _kKey = 'dns_region';

  static Future<DnsRegion> load() async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(_kKey);
      switch (s) {
        case 'china':    return DnsRegion.china;
        case 'overseas': return DnsRegion.overseas;
        default:         return DnsRegion.auto;
      }
    } catch (_) {
      return DnsRegion.auto;
    }
  }

  static Future<void> save(DnsRegion r) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_kKey, r.name);
    } catch (_) {/* ignore */}
  }

  /// 本次连接是否采用「海外方案」(= 不加 airlane-cn 的国内直连条件)。
  /// auto 时只有【确知在境外】才返回 true；判定失败/在境内一律按中国方案(false)，
  /// 保证国内用户不会因探测失败而丢掉防污染分流。调用方须在隧道未连接时调用(测的是本机出口)。
  static Future<bool> effectiveOverseas() async {
    final r = await load();
    if (r == DnsRegion.china) return false;
    if (r == DnsRegion.overseas) return true;
    final inCn = await FreeNodeService.instance.egressInChina();
    return inCn == false;   // 仅在确知非中国时走海外方案
  }
}
