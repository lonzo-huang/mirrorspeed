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

  @override
  Stream<VpnStage> get stageStream => _useDesktopRunner
      ? _win!.stageStream
      : _stage.receiveBroadcastStream().map(_mapStage);

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

  VpnStage _mapStage(dynamic e) => _mapStageName('$e');

  VpnStage _mapStageName(String s) {
    switch (s) {
      case 'connecting':    return VpnStage.connecting;
      case 'connected':     return VpnStage.connected;
      case 'disconnecting': return VpnStage.disconnecting;
      default:              return VpnStage.disconnected;
    }
  }
}
