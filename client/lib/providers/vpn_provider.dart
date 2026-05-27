import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // PlatformException + rootBundle
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';
import '../models/server_config.dart';
import '../services/ws_relay_service.dart';
import '../env.dart';

enum VpnStatus    { disconnected, connecting, connected, disconnecting, error }
enum VpnProtocol  { direct, relay }
/// 路由模式
/// - [global]：全局模式，所有流量走 VPN（0.0.0.0/0）
/// - [smart] ：智能模式，中国大陆 IP 直连，境外流量走 VPN
enum RoutingMode  { global, smart }

class VpnProvider extends ChangeNotifier {
  VpnStatus     _status        = VpnStatus.disconnected;
  ServerConfig? _activeServer;
  int?          _elapsedSecs;
  String?       _error;
  Timer?        _timer;
  Timer?        _fallbackTimer;
  StreamSubscription<VpnStage>? _stageSub;

  VpnProtocol        _protocol         = VpnProtocol.direct;
  bool               _switchingToRelay = false;
  final WsRelayService _relay          = WsRelayService();

  RoutingMode        _routingMode      = RoutingMode.global;
  List<String>?      _cachedNonCnRoutes;   // 懒加载，首次连接时计算并缓存

  VpnStatus     get status       => _status;
  ServerConfig? get activeServer => _activeServer;
  int?          get elapsedSecs  => _elapsedSecs;
  String?       get error        => _error;
  VpnProtocol   get protocol     => _protocol;
  bool          get isRelayMode  => _protocol == VpnProtocol.relay;
  RoutingMode   get routingMode  => _routingMode;

  bool get isConnected => _status == VpnStatus.connected;
  bool get isBusy      => _status == VpnStatus.connecting ||
                          _status == VpnStatus.disconnecting;

  // ── 初始化（app 启动时调用一次）────────────────────────────
  Future<void> initialize() async {
    await WireGuardFlutter.instance.initialize(interfaceName: 'wg0');
    _stageSub = WireGuardFlutter.instance.vpnStageSnapshot.listen(_onStage);

    // 恢复上次选择的路由模式
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('routing_mode');
    if (saved == RoutingMode.smart.name) {
      _routingMode = RoutingMode.smart;
      notifyListeners();
    }
  }

  // ── 切换路由模式 ─────────────────────────────────────────
  Future<void> setRoutingMode(RoutingMode mode) async {
    if (_routingMode == mode) return;
    _routingMode       = mode;
    _cachedNonCnRoutes = null; // 切换模式时清除缓存，强制重新计算
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('routing_mode', mode.name);
  }

  void _onStage(VpnStage stage) {
    switch (stage) {
      case VpnStage.connected:
        if (_switchingToRelay) {
          // 中继模式握手成功，可以放心取消计时器
          _fallbackTimer?.cancel();
        } else {
          // 直连模式：Android VPN 接口已 UP，但 WireGuard 握手可能还没完成。
          // 不在此处取消计时器，等连通性验证通过后再取消。
          _postConnectCheck(_activeServer);
        }
        _status = VpnStatus.connected;
        _startTimer();
      case VpnStage.connecting:
        _status = VpnStatus.connecting;
      case VpnStage.disconnected:
        _status = VpnStatus.disconnected;
        _stopTimer();
        // 中继切换过程中不清除 activeServer
        if (!_switchingToRelay && _activeServer != null && _error == null) {
          _activeServer = null;
        }
        _switchingToRelay = false;
      case VpnStage.disconnecting:
        _status = VpnStatus.disconnecting;
      default:
        break;
    }
    notifyListeners();
  }

  // ── 连接（直连 WireGuard，12 秒超时后自动回退到 WebSocket 中继）──
  Future<void> connect(ServerConfig server) async {
    _error            = null;
    _status           = VpnStatus.connecting;
    _activeServer     = server;
    _protocol         = VpnProtocol.direct;
    _switchingToRelay = false;
    _fallbackTimer?.cancel();
    notifyListeners();

    try {
      // 智能模式：覆盖 AllowedIPs 为非中国大陆 IP 段
      final wgConf = _routingMode == RoutingMode.smart
          ? await _applySmartRouting(server.wgConf, excludeIp: null)
          : server.wgConf;

      await WireGuardFlutter.instance.startVpn(
        serverAddress:            '${server.endpoint}:${server.port}',
        wgQuickConfig:            wgConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 12 秒内未收到 connected 事件 → 自动切换中继
      _fallbackTimer = Timer(
        const Duration(seconds: 12),
        () => _switchToRelay(server),
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_server_id', server.id);
    } on PlatformException catch (e) {
      if (e.code == 'Permissions are not given' ||
          (e.message ?? '').contains('Permissions are not given')) {
        _error  = '请在刚才弹出的对话框中允许 VPN，然后重新点击连接';
        _status = VpnStatus.disconnected;
      } else {
        _error  = e.message ?? e.toString();
        _status = VpnStatus.error;
      }
      notifyListeners();
    } catch (e) {
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  // ── WebSocket 中继回退 ───────────────────────────────────────
  // [force] = true：由连通性验证失败触发，此时 status 已是 connected
  //            但流量实际不通，需要强制切换。
  Future<void> _switchToRelay(ServerConfig server, {bool force = false}) async {
    if (!force && _status == VpnStatus.connected) return; // 正常直连已成功，无需切换

    debugPrint('[VPN] ${force ? '连通性验证失败' : '直连 12 秒超时'}，切换 WebSocket 中继...');
    _switchingToRelay = true;
    _protocol         = VpnProtocol.relay;
    _status           = VpnStatus.connecting;
    _error            = null;
    notifyListeners();

    // 停止正在进行的直连尝试
    try { await WireGuardFlutter.instance.stopVpn(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));

    // wstunnel v9.7+ 协议：路径 /v1/events + JWT（secret: "champignonfrais"）
    // Nginx /secure-tunnel/ 代理 → wstunnel:2080 → WireGuard UDP
    final wsBaseUrl = 'wss://${server.endpoint}/secure-tunnel';

    // 解析服务器 IP，用于在 AllowedIPs 中排除（防止 WebSocket 中继回环）
    // 此时 VPN 未启动，DNS 走物理网卡，域名本身不被封所以能正常解析
    String? serverIp;
    try {
      final addrs = await InternetAddress.lookup(server.endpoint)
          .timeout(const Duration(seconds: 5));
      serverIp = addrs
          .firstWhere((a) => a.type == InternetAddressType.IPv4,
              orElse: () => addrs.first)
          .address;
      debugPrint('[VPN] 服务器 IP 解析成功: $serverIp');
    } catch (e) {
      debugPrint('[VPN] 服务器 IP 解析失败，使用子网回退模式: $e');
    }

    try {
      final localPort = await _relay.start(wsBaseUrl, server.port);
      final relayConf = await _buildRelayConf(server.wgConf, localPort, serverIp);

      await WireGuardFlutter.instance.startVpn(
        serverAddress:            '127.0.0.1:$localPort',
        wgQuickConfig:            relayConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 中继模式额外等 20 秒
      _fallbackTimer?.cancel();
      _fallbackTimer = Timer(const Duration(seconds: 20), () async {
        if (_status != VpnStatus.connected) {
          await _relay.stop();
          _error  = '无法连接到 VPN（直连与中继均失败，请检查网络）';
          _status = VpnStatus.error;
          notifyListeners();
        }
      });
    } on PlatformException catch (e) {
      await _relay.stop();
      _error  = e.message ?? e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    } catch (e) {
      await _relay.stop();
      _error  = '中继连接失败: $e';
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  /// 将直连配置改写为中继模式配置。
  ///
  /// 路由策略：
  ///   A) serverIp 已解析（正常情况）→ 全隧道模式
  ///      AllowedIPs = 0.0.0.0/0 排除 serverIp/32
  ///      - 所有流量（含 DNS）走 VPN，由 VPN 服务器代理访问互联网
  ///      - WebSocket 中继流量发往 serverIp → 走物理网卡 → 不回环
  ///      - DNS 走 VPN 隧道，不存在污染问题，无需修改 DNS 配置
  ///
  ///   B) serverIp 解析失败（极少见）→ 子网回退模式
  ///      AllowedIPs = VPN 子网（10.200.0.0/24）
  ///      - 仅 VPN 内网流量走隧道，互联网流量走物理网卡
  ///      - DNS 走物理网卡，国内 DNS 会污染境外域名
  ///      - 降级为国内 DNS（114.114.114.114）以保证基本可用
  Future<String> _buildRelayConf(String wgConf, int relayPort, String? serverIp) async {
    // 1. Endpoint 改为本地中继端口
    var conf = wgConf.replaceAll(
      RegExp(r'Endpoint\s*=\s*\S+'),
      'Endpoint     = 127.0.0.1:$relayPort',
    );

    // 2. AllowedIPs（根据路由模式 + serverIp 可用性决定）
    String allowedIps;
    if (serverIp != null) {
      if (_routingMode == RoutingMode.smart) {
        // 智能模式：排除中国IP + 服务器IP（防 WebSocket 中继回环）
        final routes = await _getSmartRoutes(excludeIp: serverIp);
        allowedIps = routes.join(', ');
      } else {
        // 全局模式：0.0.0.0/0 排除服务器IP
        allowedIps = _ipv4AllExcept(serverIp).join(', ');
      }
    } else {
      // 无法解析服务器 IP → 退化为仅路由 VPN 子网
      final addrMatch = RegExp(r'Address\s*=\s*([\d.]+)/').firstMatch(conf);
      final vpnSubnet = addrMatch != null
          ? '${addrMatch.group(1)!.split('.').take(3).join('.')}.0/24'
          : '10.200.0.0/24';
      allowedIps = vpnSubnet;
      // 子网模式下 DNS 走物理网卡，必须用国内 DNS 否则境外域名被污染
      conf = _setDns(conf, '114.114.114.114, 223.5.5.5');
    }
    conf = conf.replaceAll(
      RegExp(r'AllowedIPs\s*=\s*[^\n]+'),
      'AllowedIPs   = $allowedIps',
    );

    return conf;
  }

  // ── 智能路由：将 WireGuard 配置的 AllowedIPs 改为非中国IP段 ──
  Future<String> _applySmartRouting(String wgConf, {required String? excludeIp}) async {
    final routes = await _getSmartRoutes(excludeIp: excludeIp);
    return wgConf.replaceAll(
      RegExp(r'AllowedIPs\s*=\s*[^\n]+'),
      'AllowedIPs   = ${routes.join(', ')}',
    );
  }

  /// 获取智能模式的 AllowedIPs 列表（非中国IP段，可选排除指定IP）。
  /// 结果在会话内缓存，切换模式时自动清除。
  Future<List<String>> _getSmartRoutes({required String? excludeIp}) async {
    if (_cachedNonCnRoutes == null) {
      final text = await rootBundle.loadString('assets/routes/cn_cidr.txt');
      final cnCidrs = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toList();
      _cachedNonCnRoutes = _computeComplementCidrs(cnCidrs);
      debugPrint('[VPN] 智能路由：加载 ${cnCidrs.length} 条中国IP段，计算 ${_cachedNonCnRoutes!.length} 条 AllowedIPs');
    }

    if (excludeIp == null) return _cachedNonCnRoutes!;

    // 从已有路由中再排除服务器IP（防中继回环）
    return _subtractIp(_cachedNonCnRoutes!, excludeIp);
  }

  /// 计算 CIDR 列表的互补集（全 IPv4 空间 MINUS 给定 CIDRs）。
  static List<String> _computeComplementCidrs(List<String> excludeCidrs) {
    // 1. 解析为 (start, end) 闭区间
    final ranges = <(int, int)>[];
    for (final cidr in excludeCidrs) {
      final slash = cidr.indexOf('/');
      if (slash < 0) continue;
      final ipParts = cidr.substring(0, slash).split('.');
      if (ipParts.length != 4) continue;
      try {
        final ip     = (int.parse(ipParts[0]) << 24) |
                       (int.parse(ipParts[1]) << 16) |
                       (int.parse(ipParts[2]) << 8)  |
                        int.parse(ipParts[3]);
        final prefix = int.parse(cidr.substring(slash + 1));
        final mask   = prefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - prefix)) - 1));
        final start  = ip & mask;
        final size   = prefix == 0 ? 0x100000000 : (1 << (32 - prefix));
        ranges.add((start, start + size - 1));
      } catch (_) { continue; }
    }

    // 2. 排序 + 合并重叠区间
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isEmpty || r.$1 > merged.last.$2 + 1) {
        merged.add(r);
      } else {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      }
    }

    // 3. 收集"空隙"作为结果
    final result = <String>[];
    int cursor   = 0;
    for (final (start, end) in merged) {
      if (cursor < start) result.addAll(_rangeToCidrs(cursor, start - 1));
      cursor = end + 1;
      if (cursor > 0xFFFFFFFF) break;
    }
    if (cursor <= 0xFFFFFFFF) result.addAll(_rangeToCidrs(cursor, 0xFFFFFFFF));
    return result;
  }

  /// 从 CIDR 列表中裁减掉单个 /32 IP（用于排除 VPN 服务器IP）。
  static List<String> _subtractIp(List<String> cidrs, String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return cidrs;
    final target = (int.parse(parts[0]) << 24) |
                   (int.parse(parts[1]) << 16) |
                   (int.parse(parts[2]) << 8)  |
                    int.parse(parts[3]);

    final result = <String>[];
    for (final cidr in cidrs) {
      final slash   = cidr.indexOf('/');
      if (slash < 0) { result.add(cidr); continue; }
      final ipParts = cidr.substring(0, slash).split('.');
      if (ipParts.length != 4) { result.add(cidr); continue; }
      try {
        final netIp  = (int.parse(ipParts[0]) << 24) |
                       (int.parse(ipParts[1]) << 16) |
                       (int.parse(ipParts[2]) << 8)  |
                        int.parse(ipParts[3]);
        final prefix = int.parse(cidr.substring(slash + 1));
        final mask   = prefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - prefix)) - 1));
        if ((target & mask) != (netIp & mask)) {
          result.add(cidr); // target 不在此 CIDR 中，直接保留
        } else {
          // target 在此 CIDR 中，用 _ipv4AllExcept 拆分
          result.addAll(_ipv4AllExcept(ip).where((r) {
            // 只保留与原 CIDR 交集的部分（防止拆分超出原范围）
            final rSlash  = r.indexOf('/');
            final rParts  = r.substring(0, rSlash).split('.');
            final rIp     = (int.parse(rParts[0]) << 24) |
                            (int.parse(rParts[1]) << 16) |
                            (int.parse(rParts[2]) << 8)  |
                             int.parse(rParts[3]);
            final rPrefix = int.parse(r.substring(rSlash + 1));
            final rMask   = rPrefix == 0 ? 0 : (0xFFFFFFFF - ((1 << (32 - rPrefix)) - 1));
            // r 的网络地址必须在原 CIDR 内
            return (rIp & mask) == (netIp & mask);
          }));
        }
      } catch (_) { result.add(cidr); }
    }
    return result;
  }

  /// 将连续 IP 区间 [start, end] 拆分为最精简的 CIDR 列表。
  static List<String> _rangeToCidrs(int start, int end) {
    if (start > end) return [];
    final cidrs = <String>[];
    int curr = start;
    while (curr <= end) {
      int prefix = 32;
      for (int p = 0; p <= 32; p++) {
        final blockSize = p == 0 ? 0x100000000 : (1 << (32 - p));
        if (curr % blockSize == 0 && curr + blockSize - 1 <= end) {
          prefix = p;
          break;
        }
      }
      cidrs.add('${_intToIp(curr)}/$prefix');
      final blockSize = prefix == 0 ? 0x100000000 : (1 << (32 - prefix));
      curr = curr + blockSize;
      if (curr > 0xFFFFFFFF) break;
    }
    return cidrs;
  }

  /// 替换或插入 WireGuard 配置中的 DNS 行
  static String _setDns(String conf, String dnsServers) {
    final line = 'DNS          = $dnsServers';
    if (conf.contains(RegExp(r'^\s*DNS\s*=', multiLine: true))) {
      return conf.replaceAll(
          RegExp(r'^\s*DNS\s*=\s*[^\n]+', multiLine: true), line);
    }
    return conf.replaceFirst(RegExp(r'\[Peer\]'), '$line\n\n[Peer]');
  }

  /// 计算覆盖整个 IPv4 地址空间但排除指定 /32 的 CIDR 列表（共 32 条）。
  ///
  /// 原理：沿二叉树从根（0.0.0.0/0）走到目标叶子（excludeIp/32），
  /// 在每一层收集"另一半"子树，这些子树的并集 = 全空间 − excludeIp/32。
  static List<String> _ipv4AllExcept(String excludeIp) {
    final parts = excludeIp.split('.');
    if (parts.length != 4) return ['0.0.0.0/0'];

    final target = ((int.tryParse(parts[0]) ?? 0) & 0xFF) << 24 |
                   ((int.tryParse(parts[1]) ?? 0) & 0xFF) << 16 |
                   ((int.tryParse(parts[2]) ?? 0) & 0xFF) << 8  |
                   ((int.tryParse(parts[3]) ?? 0) & 0xFF);

    final routes = <String>[];
    for (int pl = 0; pl < 32; pl++) {
      final bitPos  = 31 - pl;
      final bit     = (target >> bitPos) & 1;
      final prefix  = pl == 0 ? 0 : ((0xFFFFFFFF << (32 - pl)) & 0xFFFFFFFF);
      final sibling = (target & prefix) | ((1 - bit) << bitPos);
      final netMask = (0xFFFFFFFF << (32 - (pl + 1))) & 0xFFFFFFFF;
      routes.add('${_intToIp(sibling & netMask)}/${pl + 1}');
    }
    return routes;
  }

  static String _intToIp(int n) =>
      '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';

  // ── 断开 ────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _fallbackTimer?.cancel();
    _status = VpnStatus.disconnecting;
    notifyListeners();
    try {
      await WireGuardFlutter.instance.stopVpn();
      await _relay.stop();
      _protocol = VpnProtocol.direct;
    } catch (e) {
      _error  = e.toString();
      _status = VpnStatus.error;
      notifyListeners();
    }
  }

  // ── 切换服务器 ───────────────────────────────────────────────
  Future<void> switchServer(ServerConfig server) async {
    if (isConnected) await disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    await connect(server);
  }

  // ── 计时器 ───────────────────────────────────────────────────
  void _startTimer() {
    _elapsedSecs = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSecs = (_elapsedSecs ?? 0) + 1;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _elapsedSecs = null;
  }

  // ── 连通性验证（直连模式握手后约 4 秒执行）──────────────────
  // WireGuard UDP 被 GFW 过滤时，Android VPN 接口仍会报 connected，
  // 但实际流量无法通过。通过请求外网地址判断隧道是否真正打通。
  Future<void> _postConnectCheck(ServerConfig? server) async {
    await Future.delayed(const Duration(seconds: 4));
    // 如果已切换中继或已断开，跳过
    if (_status != VpnStatus.connected || _protocol == VpnProtocol.relay || server == null) return;

    bool ok = false;
    try {
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      ok = res.statusCode == 204 || res.statusCode < 400;
    } catch (_) {}

    if (ok) {
      _fallbackTimer?.cancel(); // 流量畅通，取消中继切换计时器
      debugPrint('[VPN] 连通性验证成功，保持直连');
    } else {
      // UDP 握手失败或流量被墙，立即切换 WebSocket 中继
      debugPrint('[VPN] 连通性验证失败，切换 WebSocket 中继');
      await _switchToRelay(server, force: true);
    }
  }

  // ── 延迟测量（请求各自服务器的 health 端点）──────────────────
  // 每台 VPN 服务器单独测量，反映从用户当前网络到该服务器的真实延迟。
  Future<void> measureLatencies(List<ServerConfig> servers) async {
    await Future.wait(servers.map((s) async {
      try {
        final sw = Stopwatch()..start();
        await http.get(
          Uri.parse('https://${s.endpoint}/vpn-api/health'),
        ).timeout(const Duration(seconds: 5));
        sw.stop();
        s.latencyMs = sw.elapsedMilliseconds;
      } catch (_) {
        s.latencyMs = null;
      }
      notifyListeners();
    }));
  }

  String get elapsedFormatted {
    final s   = _elapsedSecs ?? 0;
    final h   = s ~/ 3600;
    final m   = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _stageSub?.cancel();
    _timer?.cancel();
    _relay.stop();
    super.dispose();
  }
}
