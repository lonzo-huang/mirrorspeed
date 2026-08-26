import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../brand.dart';
import '../models/free_node.dart';
import '../services/free_node_service.dart';
import '../vpn/proxy_core_engine.dart';
import '../vpn/singbox_config.dart';
import '../vpn/vpn_engine.dart';
import '../services/app_proxy_store.dart';

/// 「共享节点」(免费机场，走 sing-box)状态管理，与 WireGuard 的 [VpnProvider] 平行。
/// 两条隧道系统级互斥：连接共享节点前先停 WireGuard（[onNeedStopOther]）。
class SharedNodeProvider extends ChangeNotifier {
  final ProxyCoreEngine _engine = ProxyCoreEngine();

  /// 连接前需要停掉的另一条隧道（WireGuard）。由 app 层注入。
  Future<void> Function()? onNeedStopOther;

  List<FreeNode> _nodes = [];
  final Map<String, int> _latency = {};   // fingerprint → ms（-1=不可达）
  FreeNode? _active;
  FreeNode? _selected;   // 最近选择的共享节点（断开后保留，供首屏统一入口再连）
  bool _preferShared = false;   // 用户当前偏好档位：true=共享，false=优质
  VpnStage  _stage = VpnStage.disconnected;
  bool      _loading = false;
  bool      _testing = false;
  int       _tested = 0;
  String?   _error;

  List<FreeNode> get nodes => _nodes;
  FreeNode?      get active => _active;
  FreeNode?      get selected => _selected;
  bool           get preferShared => _preferShared;
  VpnStage       get stage => _stage;
  bool           get loading => _loading;
  bool           get testing => _testing;
  int            get tested => _tested;
  String?        get error => _error;
  bool get isConnected  => _stage == VpnStage.connected;
  bool get isConnecting => _stage == VpnStage.connecting;
  bool get isBusy       => _stage == VpnStage.connecting || _stage == VpnStage.disconnecting;
  bool get isDisconnecting => _stage == VpnStage.disconnecting;
  int? latencyOf(FreeNode n) => _latency[n.fingerprint];

  StreamSubscription? _stageSub;

  SharedNodeProvider() {
    _stageSub = _engine.stageStream.listen((s) {
      _stage = s;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _stageSub?.cancel();
    super.dispose();
  }

  /// 拉取精选清单（clash_top50.yaml）。
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

  /// 并发 TCP 测速（仅测服务器可达性，非代理可用性）；按延迟排序、不可达沉底。
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

  /// 由 VpnProvider.connect 调用：用户改连优质节点时清掉共享偏好。
  void clearPreferShared() { _preferShared = false; }

  // ── 验证式连接：连上后经隧道实测出口，不通则自动换下一个候选（#1 兜底）──────
  bool _autoTrying = false;
  String? _tryingName;
  bool get autoTrying => _autoTrying;
  String? get tryingName => _tryingName;
  // 用户在「智能连接/验证连接」进行中点了断开 → 置位让进行中的循环立即收手，
  // 否则会与用户的 disconnect 抢连接，出现「系统已连/界面连接中」的错位卡死。
  bool _abort = false;

  /// 智能连接：从 [start] 开始，连上后实测能否访问外网(gstatic 204)，不通就按延迟
  /// 依次换下一个节点，直到找到能真正翻墙的。这是对"清单里混坏节点"的客户端兜底。
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
      await connect(cand);
      final up = await _waitStage(VpnStage.connected, const Duration(seconds: 9));
      if (_abort) break;
      if (up && await _probeEgress()) {
        _autoTrying = false; _tryingName = null; notifyListeners();
        return;   // 找到能用的
      }
      await _teardown();   // 不通 → 停掉换下一个（内部拆除，不打断本循环）
    }
    _autoTrying = false; _tryingName = null;
    // 被用户打断则不覆盖状态（disconnect 会把它带到 disconnected）。
    if (!_abort) {
      _error = '该区域暂无可真正访问外网的免费节点，请刷新或换一个';
      notifyListeners();
    }
  }

  static bool _isZh() => Platform.localeName.toLowerCase().startsWith('zh');

  /// 手动点选专用：只连**指定**节点并验证真实出口，**绝不自动跳转到其它节点**。
  /// 返回 true=连上且能访问外网；false=没连上、或连上但不通外网（此时已断开并置 [error]）。
  /// 与 [connectSmart]（智能选择用，失败会依延迟换下一个）相对——用户明确点了某个
  /// 节点时，期望就是这个节点，不该被悄悄换掉。
  Future<bool> connectVerified(FreeNode node) async {
    _abort = false;
    _error = null; notifyListeners();
    await connect(node);
    final up = await _waitStage(VpnStage.connected, const Duration(seconds: 9));
    if (_abort) return false;   // 用户中途断开
    if (up && await _probeEgress()) {
      _error = null; notifyListeners();
      return true;   // 连上且真能翻墙
    }
    // 连上但不通外网 / 根本没连上 → 断开并提示，不跳别的节点。
    final wasUp = up;
    await disconnect();
    final zh = _isZh();
    _error = wasUp
        ? (zh ? '该节点已连接，但无法访问外网。请换一个节点或用「智能选择」。'
              : 'Connected, but no internet through this node. Try another, or use Auto-select.')
        : (zh ? '该节点连接失败。请换一个节点或用「智能选择」。'
              : 'Could not connect to this node. Try another, or use Auto-select.');
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

  Future<bool> _waitStage(VpnStage want, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_abort) return _stage == want;   // 用户已请求断开，别再空等
      if (_stage == want) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _stage == want;
  }

  /// 经隧道实测外网可达性（gstatic generate_204）。
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

  /// 连接某个共享节点。先停 WireGuard（系统级只允许一条隧道）。
  /// [applyAppProxy]=false 时走全隧道(不分应用)——广告加载专用，确保本 App 的广告
  /// 请求也经隧道出去(否则白名单没包含本 App 会导致广告仍加载不了)。
  Future<void> connect(FreeNode node, {bool applyAppProxy = true}) async {
    _error = null;
    _selected = node;
    _preferShared = true;
    // 兜底：进入连接前先断开系统上的所有本 App VPN——
    // ① 停掉另一条引擎（优质 WireGuard），系统级只允许一条隧道；
    // ② 若本引擎(sing-box)上一次还有残留隧道，先彻底拆掉再起新的，
    //    防止「残留连接」和与其它客户端的相互干扰/冲突。
    // 注：Android/桌面只能停「本 App 自己」的 VPN；但在 Android 上建立新隧道会由系统
    //    自动顶替掉任何其它 App 的现有 VPN（系统同时只允许一条），故也能避免外部冲突。
    try { await onNeedStopOther?.call(); } catch (_) {}
    if (_stage != VpnStage.disconnected) {
      try { await _teardown(); } catch (_) {}
    }
    _active = node;
    notifyListeners();
    try {
      // 分应用黑白名单对免费节点生效：
      // - Android：sing-box tun include/exclude_package（Android 专属字段）。仅中文壳
      //   注入——分应用是中国市场特性，否则默认白名单只放 26 个 App 会「连上但应用没走
      //   VPN」，故非中文一律全隧道。
      // - Windows/桌面：用 sing-box process_name 路由规则(按进程名)，存的是 exe 名；
      //   opt-in(默认空)，不受 isZh 限制。
      List<String>? inc, exc, incProc, excProc;
      if (applyAppProxy && await AppProxyStore.loadEnabled()) {
        final pkgs = (await AppProxyStore.loadPkgs()).toList();
        if (pkgs.isNotEmpty) {
          final white = await AppProxyStore.loadMode() == 'white';
          if (Platform.isAndroid && Brand.isZh) {
            if (white) { inc = pkgs; } else { exc = pkgs; }
          } else if (Platform.isWindows) {
            if (white) { incProc = pkgs; } else { excProc = pkgs; }
          }
        }
      }
      debugPrint('[APPPROXY-SB] inc=${inc?.length ?? 0} exc=${exc?.length ?? 0} '
          'incProc=${incProc?.length ?? 0} excProc=${excProc?.length ?? 0}');
      final cfg = SingboxConfig.build(node, smart: false,
          includePackages: inc, excludePackages: exc,
          includeProcesses: incProc, excludeProcesses: excProc);
      await _engine.start(EngineStartParams(singboxConfig: cfg));
    } catch (e) {
      _error = '$e';
      _active = null;
      notifyListeners();
    }
  }

  /// 为加载广告临时连一个随机共享节点（国内直连加载不了广告时用）。
  /// 已有共享连接则直接复用；否则拉取+测速后挑一个低延迟可达节点连上并等待就绪。
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
    // 低延迟前若干个里随机挑一个（分散负载）。
    final head = pool.take(pool.length < 8 ? pool.length : 8).toList()..shuffle();
    await connect(head.first, applyAppProxy: false);   // 广告全隧道
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!isConnected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // 隧道建好后给路由/DNS 一点稳定时间，广告 SDK 才能连出去。
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  /// 用户主动断开：打断进行中的智能/验证连接，再拆隧道。
  Future<void> disconnect() async {
    _abort = true;                  // 让 connectSmart/connectVerified 立即收手
    _autoTrying = false; _tryingName = null;
    await _teardown();
  }

  /// 拆除当前隧道并把状态确定性地带到 disconnected。connectSmart 换节点时内部复用
  /// （不置 _abort，故不会打断自身循环）。
  Future<void> _teardown() async {
    // 立即反映「断开中」，避免拆除等待期间点了没反应。
    _stage = VpnStage.disconnecting;
    notifyListeners();
    try {
      await _engine.stop();
    } catch (_) {}
    // "disconnected" 事件正常由原生 onDestroy 发出 = sing-box 的 VpnService 已被系统
    // 完全销毁、VPN 已释放。必须等到这个信号再返回（VpnProvider.connect 据此才启动
    // WireGuard），否则 WG 会和系统的 VPN 拆除回调在主线程撞车 → App 被强杀。
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (_stage != VpnStage.disconnected && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // 兜底：即便始终没收到原生 disconnected 事件（跨进程 :singbox 广播在连续
    // start/stop 后可能丢失），也强制把状态归位到 disconnected——否则 UI 会永远卡在
    // 「连接中/断开中」busy 态，既不能断也不能重连（本次修复的正是这个卡死）。
    _stage  = VpnStage.disconnected;
    _active = null;
    notifyListeners();
  }
}
