import 'package:shared_preferences/shared_preferences.dart';
import '../services/free_node_service.dart';

/// DNS / 分流「地区方案」：
/// - auto     ：按当前网络环境自动选（确知境外→海外方案；境内/未知→中国大陆方案）
/// - china    ：强制中国大陆方案（airlane-cn 规则集：国内直连 + 防污染 DNS）
/// - overseas ：强制海外方案（无 GFW，不做 geo-cn 分流，国内外都经节点）
enum DnsRegion { auto, china, overseas }

class DnsRegionStore {
  DnsRegionStore._();
  static const _kKey = 'dns_region';

  static Future<DnsRegion> load() async {
    try {
      switch ((await SharedPreferences.getInstance()).getString(_kKey)) {
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

  /// 本次连接是否采用海外方案(= 不加 airlane-cn 国内直连)。
  /// auto 时仅【确知在境外】才 true；判定失败/境内一律按中国方案(false),保证国内不丢防污染分流。
  /// 须在隧道未连接时调用(测的是本机真实出口)。
  static Future<bool> effectiveOverseas() async {
    final r = await load();
    if (r == DnsRegion.china) return false;
    if (r == DnsRegion.overseas) return true;
    final inCn = await FreeNodeService.instance.egressInChina();
    return inCn == false;   // 仅确知非中国才走海外方案
  }
}
