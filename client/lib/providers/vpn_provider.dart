import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // PlatformException + rootBundle
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amneziawg_flutter/amneziawg_flutter.dart';
import '../models/server_config.dart';
import '../services/ws_relay_service.dart';
import '../services/port_hopping.dart';
import '../env.dart';

export 'package:amneziawg_flutter/amneziawg_flutter.dart' show VpnStage;

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

  // 会话级钉死端口：UDP 直连时在 connect() 时基于时间计算一次并保存。
  // 一旦连接建立，整个会话期间复用此端口，绝不重算——即使将来加入断线
  // 自动重连，也必须沿用此值，避免跨小时窗口时端口漂移。disconnect() 清空。
  int?               _sessionPort;

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
    await AmneziaWG.instance.initialize(interfaceName: 'mirrorspeed');
    _stageSub = AmneziaWG.instance.vpnStageSnapshot.listen(_onStage);

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
          // 中继模式握手成功：取消超时计时器，重置切换标志
          _fallbackTimer?.cancel();
          _switchingToRelay = false;
          // 验证中继流量是否真正畅通（5 秒后）
          _postRelayCheck(_activeServer);
        } else {
          // 直连模式：Android VPN 接口已 UP，但 AWG 握手可能还没完成。
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
        // 中继切换过程中不清除 activeServer；
        // _switchingToRelay 在此处故意不重置——需等到
        // relay 的 startVpn 触发 connected 后才置 false，
        // 以便 connected 分支能正确识别并取消 _fallbackTimer。
        if (!_switchingToRelay && _activeServer != null && _error == null) {
          _activeServer = null;
        }
      case VpnStage.disconnecting:
        _status = VpnStatus.disconnecting;
      default:
        break;
    }
    notifyListeners();
  }

  // ── 连接（三层防护机制）───────────────────────────────────────────────────────
  //
  //  层 1：AmneziaWG 直连 + 端口跳变（AWG 包混淆，GFW 难以识别）
  //  层 2：wstunnel WebSocket over HTTPS 443（流量伪装为 HTTPS）
  //  层 3：Cloudflare Tunnel（服务器 IP 完全隐藏，GFW 无从封锁）
  //
  Future<void> connect(ServerConfig server) async {
    _error            = null;
    _status           = VpnStatus.connecting;
    _activeServer     = server;
    _protocol         = VpnProtocol.direct;
    _switchingToRelay = false;
    _fallbackTimer?.cancel();
    _sessionPort      = null;   // 用户主动连接 = 一次重连，按当前时间重新算端口
    notifyListeners();

    try {
      // 1. 计算实际连接端口（端口跳变 or 固定端口），并钉死到本次会话。
      //    端口只在此处基于时间计算一次；连上后整个会话不再改变。
      final effectivePort = _computePort(server);
      _sessionPort = effectivePort;

      // 2. 将 AWG 配置中的端点端口替换为跳变端口
      String wgConf = _routingMode == RoutingMode.smart
          ? await _applySmartRouting(server.wgConf, excludeIp: null)
          : server.wgConf;
      wgConf = PortHoppingService.instance
          .rewriteEndpointPort(wgConf, effectivePort);

      debugPrint('[VPN] 直连 AmneziaWG，端口=$effectivePort');

      await AmneziaWG.instance.startVpn(
        serverAddress:            '${server.endpoint}:$effectivePort',
        wgQuickConfig:            wgConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 12 秒内未收到 connected 事件 → 自动切换 wstunnel 443 中继（层 2）
      // 使用 relayHost（域名）而非 endpoint（可能为 IP），确保 TLS 证书匹配
      _fallbackTimer = Timer(
        const Duration(seconds: 12),
        () => _switchToRelay(server, relayBaseUrl: 'wss://${server.relayHost}'),
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

  /// 计算端口（端口跳变 or 固定端口）。
  ///
  /// 本次会话已钉死端口时（_sessionPort 非空）直接复用，确保连接建立后
  /// 即便 connect() 被再次进入（如断线自动重连）也不会跨小时窗口换端口。
  /// 只有在主动 disconnect() 清空 _sessionPort 后，才会重新基于时间计算。
  int _computePort(ServerConfig server) {
    if (_sessionPort != null) return _sessionPort!;
    if (server.portSecret == null || server.portSecret!.isEmpty) {
      return server.port;
    }
    // 尝试当前 hour，连通性验证失败后 fallback 到 wstunnel，不在此处遍历 ±1
    return PortHoppingService.instance
        .computePort(server.portSecret!, hourOffset: 0);
  }

  // AWG 在服务器上的内部监听端口（wstunnel --restrict-to 匹配此端口）。
  // 注意：server.port 是对外暴露的端口（可能经过 iptables DNAT），
  // 而 wstunnel 直接连接 AWG 内部端口（不经过 DNAT），因此必须用固定值 51820。
  static const int _awgInternalPort = 51820;

  // ── 中继回退（层 2 = wstunnel 443，层 3 = Cloudflare Tunnel）─────────────────
  //
  // [relayBaseUrl]  中继服务器 WebSocket 基础 URL，不含路径（如 wss://host.com）
  //                 ws_relay_service 会自动追加 /secure-tunnel/v1/events
  // [force]         true = 由连通性验证失败强制触发
  //
  Future<void> _switchToRelay(
    ServerConfig server, {
    required String relayBaseUrl,
    bool force = false,
  }) async {
    // 立即取消定时器：防止 _postConnectCheck 和定时器同时触发时的竞争条件
    // （两者都可能在 T≈12s 时触发，并发调用会导致 _localPort 被清零后再 ! 解引用）
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    if (!force && _status == VpnStatus.connected) return; // 直连已成功，无需切换

    final primaryBase = 'wss://${server.relayHost}';
    final isCf        = relayBaseUrl != primaryBase;
    debugPrint('[VPN] 切换到${isCf ? ' Cloudflare' : ' wstunnel-443'} 中继: $relayBaseUrl');

    _switchingToRelay = true;
    _protocol         = VpnProtocol.relay;
    _status           = VpnStatus.connecting;
    _error            = null;
    notifyListeners();

    // 停止正在进行的隧道
    try { await AmneziaWG.instance.stopVpn(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 600));

    // 解析服务器 IP，用于在 AllowedIPs 中排除（防止 WebSocket 中继回环）
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
      // ws_relay_service 追加 /v1/events；nginx 代理 /secure-tunnel/ → wstunnel
      // JWT 中的 rp 必须等于 AWG 内部监听端口（51820），与 wstunnel --restrict-to 一致。
      // server.port 是对外暴露端口（可能经 iptables DNAT），不适合此处。
      final localPort = await _relay.start(
          '$relayBaseUrl/secure-tunnel', _awgInternalPort);
      final relayConf = await _buildRelayConf(server.wgConf, localPort, serverIp);

      await AmneziaWG.instance.startVpn(
        serverAddress:            '127.0.0.1:$localPort',
        wgQuickConfig:            relayConf,
        providerBundleIdentifier: kProviderBundle,
      );

      // 等 20 秒确认连通；超时则尝试下一层
      _fallbackTimer = Timer(const Duration(seconds: 20), () async {
        if (_status != VpnStatus.connected) {
          await _relay.stop();
          final cfUrl = server.cfRelayUrl;
          if (!isCf && cfUrl != null) {
            // 层 3：wstunnel-443 超时 → 尝试 Cloudflare Tunnel
            await _switchToRelay(server, relayBaseUrl: cfUrl, force: true);
          } else {
            // 所有层均失败
            _error  = '无法连接到 VPN（全部线路尝试失败，请检查网络后重试）';
            _status = VpnStatus.error;
            notifyListeners();
          }
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

  // ── 智能路由：将 AWG 配置的 AllowedIPs 改为非中国IP段 ────────────────────
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
    _sessionPort      = null;    // 主动断开后，下次连接重新基于时间计算端口
    _switchingToRelay = false;   // 确保 disconnected 事件不误判为中继切换中
    _status = VpnStatus.disconnecting;
    notifyListeners();
    try {
      await AmneziaWG.instance.stopVpn();
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

  /// 通用连通性探测：经隧道请求外网 generate_204，5 秒超时。
  /// 返回 true 表示隧道内流量真正畅通。
  Future<bool> _probeConnectivity() async {
    try {
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 204 || res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  // ── App 从后台/深度休眠恢复时调用（由 app.dart 生命周期监听触发）──────────
  //
  // 长时间 Doze 休眠后存在一个无法自愈的死锁场景：
  //   1. 休眠期间 PersistentKeepalive(25s) 定时器被系统冻结，服务端
  //      conntrack UDP 条目（默认 120s）过期；
  //   2. 同时服务端每小时端口轮换可能已刷掉本会话钉死端口的 DNAT 规则；
  //   → 唤醒后隧道仍显示 connected，但发往钉死端口的包命中 NEW 状态、
  //     无匹配规则被丢弃；WireGuard 重握手仍打向同一死端口，永远连不上。
  //
  // 这里在恢复时主动探测，若隧道已死则整体重连——disconnect() 清空
  // _sessionPort，connect() 随即按当前时间重新派生一个有效端口。
  Future<void> onAppResumed() async {
    if (_status != VpnStatus.connected || _switchingToRelay) return;
    final server = _activeServer;
    if (server == null) return;

    // 给系统网络栈一点恢复时间再探测，避免误判
    await Future.delayed(const Duration(seconds: 2));
    if (_status != VpnStatus.connected || _switchingToRelay) return;

    if (await _probeConnectivity()) {
      debugPrint('[VPN] resume 健康检查通过，保持连接');
      return;
    }

    debugPrint('[VPN] resume 健康检查失败，隧道已死，重连中…');
    await disconnect();                                  // 清空 _sessionPort
    await Future.delayed(const Duration(milliseconds: 400));
    await connect(server);                               // 重新派生端口并连接
  }

  // ── 连通性验证（直连模式握手后约 4 秒执行）──────────────────
  // AWG UDP 被 GFW 过滤时，Android VPN 接口仍会报 connected，
  // 但实际流量无法通过。通过请求外网地址判断隧道是否真正打通。
  Future<void> _postConnectCheck(ServerConfig? server) async {
    await Future.delayed(const Duration(seconds: 4));
    // 如果已切换中继或已断开，跳过
    if (_status != VpnStatus.connected || _protocol == VpnProtocol.relay || server == null) return;
    // 如果定时器已经抢先触发了 _switchToRelay，跳过避免并发
    if (_switchingToRelay) return;

    final ok = await _probeConnectivity();

    if (ok) {
      _fallbackTimer?.cancel(); // 流量畅通，取消中继切换计时器
      debugPrint('[VPN] 连通性验证成功，保持直连');
    } else {
      // UDP 握手失败或流量被墙，立即切换 wstunnel 443 中继（层 2）
      debugPrint('[VPN] 连通性验证失败，切换 wstunnel 443 中继');
      await _switchToRelay(
        server,
        relayBaseUrl: 'wss://${server.relayHost}',  // 域名，确保 TLS 匹配
        force: true,
      );
    }
  }

  // ── 连通性验证（中继模式，握手后约 5 秒执行）────────────────
  // 中继模式下 AWG 握手可能成功（ICMP/UDP 层通了），但 WebSocket
  // 出口侧流量仍可能不通（如 wstunnel 路由配置错误）。
  // 5 秒后用同一个 HTTP 204 检测实际网络可达性；
  // 失败则尝试层 3（Cloudflare Tunnel），或报错。
  Future<void> _postRelayCheck(ServerConfig? server) async {
    await Future.delayed(const Duration(seconds: 5));
    if (_status != VpnStatus.connected || _protocol != VpnProtocol.relay || server == null) return;

    bool ok = false;
    try {
      final res = await http.get(
        Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
      ).timeout(const Duration(seconds: 8));
      ok = res.statusCode == 204 || res.statusCode < 400;
    } catch (_) {}

    if (ok) {
      debugPrint('[VPN] 中继连通性验证成功');
    } else {
      debugPrint('[VPN] 中继连通性验证失败，尝试 Cloudflare Tunnel（层 3）');
      await _relay.stop();
      final cfUrl = server.cfRelayUrl;
      if (cfUrl != null && cfUrl.isNotEmpty) {
        await _switchToRelay(server, relayBaseUrl: cfUrl, force: true);
      } else {
        // Cloudflare 未配置，报告失败
        _error  = '已连接但流量不通，请稍后重试或更换节点';
        _status = VpnStatus.error;
        notifyListeners();
      }
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
