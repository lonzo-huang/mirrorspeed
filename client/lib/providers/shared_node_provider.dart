import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/free_node.dart';
import '../services/free_node_service.dart';
import '../services/app_proxy_store.dart';
import '../vpn/singbox_config.dart';
import '../utils/rule_set_assets.dart';
import '../utils/dns_region.dart';
import 'vpn_provider.dart';

/// 「免费节点」的**数据/编排层**（节点清单、测速、自动换节点）。
///
/// 合并重构后它**不再拥有自己的引擎/状态机**：隧道的启停与「已连接」状态全部委托给唯一的
/// [VpnProvider]（经 runSharedTunnel / markSharedConnected / disconnect）。全 App 只有一个
/// 连接状态真相，彻底消除「优质/免费状态打架」。本类只负责：挑哪个节点、测速、连不上自动换、
/// 以及 egress 校验（因为免费清单里常混坏节点，这是客户端兜底）。
class SharedNodeProvider extends ChangeNotifier {
  final VpnProvider _vpn;

  SharedNodeProvider(this._vpn) {
    // VpnProvider 状态变化 → 本类对外的连接态 getter 也随之变 → 透传通知给监听本类的 UI。
    _vpn.addListener(_onVpn);
  }

  void _onVpn() {
    // 连接态（针对免费来源）变化时，顺带驱动速率轮询的起停。
    final connectedFree = isConnected;
    if (connectedFree && _speedTimer == null) _startSpeedPolling();
    if (!connectedFree && _speedTimer != null) _stopSpeedPolling();
    notifyListeners();
  }

  @override
  void dispose() {
    _speedTimer?.cancel();
    _vpn.removeListener(_onVpn);
    super.dispose();
  }

  // ── 节点清单 / 测速（纯数据，保持不变）──────────────────────────
  List<FreeNode> _nodes = [];
  final Map<String, int> _latency = {};   // fingerprint → ms（-1=不可达）
  FreeNode? _selected;   // 最近选择的免费节点（断开后保留，供首屏统一入口再连）
  bool _preferShared = false;   // 用户当前偏好档位：true=免费，false=优质
  bool _loading = false;
  bool _testing = false;
  int  _tested  = 0;
  String? _error;

  List<FreeNode> get nodes => _nodes;
  FreeNode?      get selected => _selected;
  bool           get preferShared => _preferShared;
  bool           get loading => _loading;
  bool           get testing => _testing;
  int            get tested => _tested;
  int? latencyOf(FreeNode n) => _latency[n.fingerprint];

  // ── 连接态：全部委托给唯一的 VpnProvider（仅当来源是 free 时才算免费已连）──────
  FreeNode? get active => _vpn.source == ConnSource.free ? _vpn.activeFreeNode : null;
  String?   get error  => _error ?? (_vpn.source == ConnSource.free ? _vpn.error : null);
  bool get isConnected     => _vpn.source == ConnSource.free && _vpn.status == VpnStatus.connected;
  bool get isConnecting     => _vpn.source == ConnSource.free && _vpn.status == VpnStatus.connecting;
  bool get isDisconnecting  => _vpn.source == ConnSource.free && _vpn.status == VpnStatus.disconnecting;
  bool get isBusy           => isConnecting || isDisconnecting;

  /// 由 VpnProvider.connect 调用：用户改连优质节点时清掉免费偏好。
  void clearPreferShared() { _preferShared = false; }

  Future<void> load() async {
    _loading = true; _error = null; notifyListeners();
    try {
      _nodes = await FreeNodeService.instance.fetch(top: true);
      if (_nodes.isEmpty) _error = '未获取到节点';
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false; notifyListeners();
    }
  }

  Future<void> testAll() async {
    if (_nodes.isEmpty || _testing) return;
    _testing = true; _tested = 0; _latency.clear(); notifyListeners();
    const conc = 40;
    for (var i = 0; i < _nodes.length; i += conc) {
      await Future.wait(_nodes.skip(i).take(conc).map((n) async {
        _latency[n.fingerprint] = await _ping(n);
        _tested++;
      }));
      notifyListeners();
    }
    _nodes.sort((a, b) {
      final la = _latency[a.fingerprint] ?? 999999;
      final lb = _latency[b.fingerprint] ?? 999999;
      return (la < 0 ? 100000 : la).compareTo(lb < 0 ? 100000 : lb);
    });
    _testing = false; notifyListeners();
  }

  Future<int> _ping(FreeNode n) async {
    final sw = Stopwatch()..start();
    Socket? s;
    try {
      s = await Socket.connect(n.server, n.port, timeout: const Duration(seconds: 3));
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      s?.destroy();
    }
  }

  // ── 验证式连接 / 自动换节点 ──────────────────────────────────────
  bool _autoTrying = false;
  String? _tryingName;
  bool get autoTrying => _autoTrying;
  String? get tryingName => _tryingName;
  bool _abort = false;

  /// 智能连接：从 [start] 开始，连上后实测能否访问外网(gstatic 204)，不通就按延迟换下一个。
  Future<void> connectSmart(FreeNode start) async {
    _abort = false;
    final others = _nodes
        .where((n) => !identical(n, start) && (_latency[n.fingerprint] ?? -1) >= 0)
        .toList()
      ..sort((a, b) => (_latency[a.fingerprint] ?? 999999).compareTo(_latency[b.fingerprint] ?? 999999));
    final queue = [start, ...others].take(6).toList();

    _autoTrying = true; _error = null; notifyListeners();
    for (final cand in queue) {
      if (_abort) break;
      _tryingName = cand.name; notifyListeners();
      await _startTunnel(cand);
      if (_abort) break;
      if (await _probeEgress()) {
        _vpn.markSharedConnected();
        _autoTrying = false; _tryingName = null; notifyListeners();
        return;   // 找到能用的
      }
      // 不通 → 继续试下一个（下一个的 runSharedTunnel 会先停掉当前）。
    }
    _autoTrying = false; _tryingName = null;
    if (!_abort) {
      await _vpn.disconnect();
      _error = '该区域暂无可真正访问外网的免费节点，请刷新或换一个';
      notifyListeners();
    }
  }

  /// 手动点选专用：只连**指定**节点并验证真实出口，绝不自动跳别的节点。
  Future<bool> connectVerified(FreeNode node) async {
    _abort = false;
    _error = null; notifyListeners();
    await _startTunnel(node);
    if (_abort) return false;
    if (await _probeEgress()) {
      _vpn.markSharedConnected();
      _error = null; notifyListeners();
      return true;
    }
    await _vpn.disconnect();
    final zh = _isZh();
    _error = zh ? '该节点连接失败或无法访问外网。请换一个节点或用「智能选择」。'
                : 'Could not connect / no internet via this node. Try another or use Auto-select.';
    notifyListeners();
    return false;
  }

  /// 智能选择：挑延迟最低的可达节点，走验证式连接。
  Future<void> connectBest() async {
    if (_nodes.isEmpty) await load();
    if (_latency.values.where((v) => v >= 0).isEmpty) await testAll();
    final alive = _nodes.where((n) => (_latency[n.fingerprint] ?? -1) >= 0).toList()
      ..sort((a, b) => (_latency[a.fingerprint] ?? 999999).compareTo(_latency[b.fingerprint] ?? 999999));
    if (alive.isEmpty) {
      _error = '暂无可达免费节点，请刷新'; notifyListeners(); return;
    }
    await connectSmart(alive.first);
  }

  /// 为加载广告临时连一个随机免费节点（国内直连加载不了广告时用）。全隧道、不验证。
  Future<void> connectRandomForAd() async {
    if (isConnected) return;
    if (_nodes.isEmpty) await load();
    if (_nodes.isEmpty) return;
    if (_latency.values.where((v) => v >= 0).isEmpty) await testAll();
    final alive = _nodes.where((n) {
      final l = _latency[n.fingerprint];
      return l != null && l >= 0;
    }).toList();
    final pool = alive.isNotEmpty ? alive : _nodes;
    final head = pool.take(pool.length < 8 ? pool.length : 8).toList()..shuffle();
    await _startTunnel(head.first, applyAppProxy: false);   // 广告全隧道
    // 隧道建好后给路由/DNS 一点稳定时间，广告 SDK 才能连出去。
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _vpn.markSharedConnected();
  }

  /// 用户主动断开：打断进行中的智能/验证连接，再经 VpnProvider 拆隧道。
  Future<void> disconnect() async {
    _abort = true;
    _autoTrying = false; _tryingName = null;
    await _vpn.disconnect();
    notifyListeners();
  }

  Future<bool> _probeEgress() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200)); // 等路由/DNS 稳定
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await c.getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 9));
      final res = await req.close().timeout(const Duration(seconds: 9));
      await res.drain();
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      c.close(force: true);
    }
  }

  /// 构建免费节点的 sing-box 配置并经 VpnProvider 启动隧道（单一引擎/状态机）。
  Future<void> _startTunnel(FreeNode node, {bool applyAppProxy = true}) async {
    _selected = node;
    _preferShared = true;
    // #1 网络预检：没网直接报错,不进连接流程。
    if (!await VpnProvider.hasActiveNetwork()) {
      _error = _isZh() ? '无网络连接，请检查 WiFi 或移动数据'
                       : 'No network. Check WiFi or mobile data.';
      _abort = true;   // 让 connectVerified/connectSmart 收手
      notifyListeners();
      return;
    }
    // 分应用黑白名单对免费节点生效（与合并前一致）。
    final rmode = (await SharedPreferences.getInstance()).getString('routing_mode');
    final isGlobal = rmode == 'global';
    List<String>? inc, exc, incProc, excProc;
    if (applyAppProxy && !isGlobal) {
      final pkgs = (await AppProxyStore.loadPkgs()).toList();
      if (pkgs.isNotEmpty) {
        final white = await AppProxyStore.loadMode() == 'white';
        if (Platform.isAndroid) {
          if (white) { inc = pkgs; } else { exc = pkgs; }
        } else if (Platform.isWindows) {
          if (white) { incProc = pkgs; } else { excProc = pkgs; }
        }
      }
    }
    // 本 App + Google Play 服务必须进隧道，否则 AdMob 广告请求走直连被墙。
    const selfPkg = 'com.mirrorspeed.vpn';
    const gmsPkg  = 'com.google.android.gms';
    if (Platform.isAndroid) {
      if (inc != null) {
        var list = inc;
        for (final p in [selfPkg, gmsPkg]) { if (!list.contains(p)) list = [...list, p]; }
        inc = list;
      }
      if (exc != null) exc = exc.where((p) => p != selfPkg && p != gmsPkg).toList();
    }
    final ipv6 = await _hasGlobalIpv6();
    final overseas = await DnsRegionStore.effectiveOverseas();
    final smartFlag = await _appleSmartRouting();
    String? cnRsPath;
    if (smartFlag && !overseas && !(Platform.isIOS || Platform.isMacOS)) {
      cnRsPath = await RuleSetAssets.cnRuleSetPath();
    }
    final cfg = SingboxConfig.build(node.outbound, smart: smartFlag,
        includePackages: inc, excludePackages: exc,
        includeProcesses: incProc, excludeProcesses: excProc,
        cnRuleSetPath: cnRsPath, overseas: overseas,
        ipv6: ipv6);
    await _vpn.runSharedTunnel(cfg, node: node);
  }

  /// 免费节点是否启用智能分流（仅 Apple；其它平台全局隧道，行为不变）。
  Future<bool> _appleSmartRouting() async {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('routing_mode');
    final smart = mode == null ? _isZh() : mode == 'smart';
    if (!smart) return false;
    return await FreeNodeService.instance.egressInChina() != false;
  }

  static bool _isZh() => Platform.localeName.toLowerCase().startsWith('zh');

  Future<bool> _hasGlobalIpv6() async {
    if (Platform.isAndroid) return false;
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv6,
          includeLinkLocal: false, includeLoopback: false);
      for (final i in ifaces) {
        if (i.addresses.any((a) => !a.isLoopback && !a.isLinkLocal)) return true;
      }
    } catch (_) {}
    return false;
  }

  // ── 速率计量（走 VpnProvider 的同一引擎）──────────────────────────
  Timer? _speedTimer;
  int _lastRx = -1, _lastTx = -1, _lastSpeedMs = 0;
  int _downBps = 0, _upBps = 0;
  bool _speedAvailable = false;

  bool   get speedAvailable   => _speedAvailable;
  String get downloadSpeedStr => _fmtBps(_downBps);
  String get uploadSpeedStr   => _fmtBps(_upBps);

  void _startSpeedPolling() {
    _speedTimer?.cancel();
    _lastRx = _lastTx = -1;
    _pollSpeed();
    _speedTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollSpeed());
  }

  void _stopSpeedPolling() {
    _speedTimer?.cancel();
    _speedTimer = null;
    _downBps = _upBps = 0;
    _speedAvailable = false;
  }

  Future<void> _pollSpeed() async {
    final r = await _vpn.sharedTransferRxTx()
        .timeout(const Duration(seconds: 3), onTimeout: () => const [-1, -1]);
    final rx = r.isNotEmpty ? r[0] : -1, tx = r.length > 1 ? r[1] : -1;
    if (rx < 0 || tx < 0) {
      if (_speedAvailable) { _speedAvailable = false; notifyListeners(); }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastRx >= 0 && _lastSpeedMs > 0) {
      final dt = (now - _lastSpeedMs) / 1000.0;
      if (dt >= 0.5) {
        _downBps = ((rx - _lastRx) / dt).round().clamp(0, 1 << 40);
        _upBps   = ((tx - _lastTx) / dt).round().clamp(0, 1 << 40);
      }
    }
    _lastRx = rx; _lastTx = tx; _lastSpeedMs = now;
    _speedAvailable = true;
    notifyListeners();
  }

  static String _fmtBps(int b) {
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB/s';
    if (b >= 1024)        return '${(b / 1024).toStringAsFixed(0)} KB/s';
    return '$b B/s';
  }
}
