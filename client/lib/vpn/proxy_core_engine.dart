import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'vpn_engine.dart';
import 'singbox_windows_runner.dart';

/// sing-box 引擎:用于「共享节点」(免费机场)。
/// - Android / iOS：原生插件(libbox + VpnService / NEPacketTunnelProvider)，
///   经 MethodChannel 'mirrorspeed/singbox' + EventChannel 调用。
/// - Windows / macOS 桌面：官方 sing-box.exe / sing-box 子进程 + wintun/utun。
/// 启动参数走 [EngineStartParams.singboxConfig]（完整 sing-box 配置，见 SingboxConfig）。
class ProxyCoreEngine implements VpnEngine {
  static const MethodChannel _control = MethodChannel('mirrorspeed/singbox');
  static const EventChannel  _stage   = EventChannel('mirrorspeed/singbox/stage');

  // 桌面（Windows）用子进程运行器。
  static final bool _useDesktopRunner =
      !kIsWeb && Platform.isWindows;
  final SingboxWindowsRunner? _win =
      (!kIsWeb && Platform.isWindows) ? SingboxWindowsRunner() : null;

  @override
  EngineKind get kind => EngineKind.singbox;

  @override
  Future<void> initialize() async {
    if (_useDesktopRunner) return;   // 桌面无需初始化
    await _control.invokeMethod('init');
  }

  /// 当前隧道归属：'premium'(优质/VpnProvider) | 'free'(免费/SharedNodeProvider) | null。
  /// 两个 provider 共用同一个原生 sing-box 服务与同一条 stage 流,各自据此只处理「属于自己」
  /// 的 stage 事件,避免互相串扰(一方连接时另一方误判自己也连上/断开)。连接前由各 provider 置位。
  static String? activeOwner;

  /// 全局唯一的 stage 广播流：只向原生 EventChannel listen 一次,多个 provider 共享。
  /// (之前每个 ProxyCoreEngine 实例各自 receiveBroadcastStream → 同一 channel 被重复 listen,
  ///  后注册者抢走事件 sink,导致另一方收不到 connected/disconnected → UI 卡死 + 断开空等。)
  static Stream<VpnStage>? _sharedStageStream;

  @override
  Stream<VpnStage> get stageStream {
    if (_useDesktopRunner) return _win!.stageStream;
    return _sharedStageStream ??=
        _stage.receiveBroadcastStream().map(_mapStageStatic).asBroadcastStream();
  }

  @override
  Future<VpnStage> stage() async {
    if (_useDesktopRunner) return _win!.stage;
    final s = await _control.invokeMethod<String>('stage');
    return _mapStageName(s ?? 'disconnected');
  }

  @override
  Future<void> start(EngineStartParams p) async {
    final cfg = p.singboxConfig;
    if (cfg == null) {
      throw ArgumentError('ProxyCoreEngine.start 需要 singboxConfig');
    }
    final json = jsonEncode(cfg);
    if (_useDesktopRunner) {
      await _win!.start(json);
      return;
    }
    await _control.invokeMethod('start', {'config': json});
  }

  @override
  Future<void> stop() async {
    if (_useDesktopRunner) { await _win!.stop(); return; }
    await _control.invokeMethod('stop');
  }

  @override
  Future<List<int>> transferRxTx() async {
    if (_useDesktopRunner) return const [-1, -1];
    final r = await _control.invokeMethod<List<dynamic>>('transferRxTx');
    if (r == null || r.length < 2) return const [-1, -1];
    return [(r[0] as num).toInt(), (r[1] as num).toInt()];
  }

  /// 原生随 "connected setup=.. check=.. cmd=.. reload=.." 上报的起隧道分步计时(诊断用)。
  static String? lastConnectedDiag;

  VpnStage _mapStageName(String s) => _mapStageStatic(s);

  static VpnStage _mapStageStatic(dynamic e) {
    final s = '$e';
    final sp = s.indexOf(' ');
    final head = sp >= 0 ? s.substring(0, sp) : s;
    if (head == 'connected' && sp >= 0) lastConnectedDiag = s.substring(sp + 1);
    switch (head) {
      case 'connecting':    return VpnStage.connecting;
      case 'connected':     return VpnStage.connected;
      case 'disconnecting': return VpnStage.disconnecting;
      default:              return VpnStage.disconnected;
    }
  }
}
