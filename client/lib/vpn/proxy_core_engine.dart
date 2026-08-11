import 'dart:convert';
import 'package:flutter/services.dart';
import 'vpn_engine.dart';

/// sing-box 引擎:用于「共享节点」(免费机场)。通过 method/event channel 调用原生
/// singbox_flutter 插件(libbox + VpnService / NEPacketTunnelProvider)。
///
/// 原生侧尚未接入(需 libbox.aar);Dart 侧接口已就绪,原生一到位即可跑通。
/// 启动参数走 [EngineStartParams.singboxConfig](完整 sing-box 配置,见 SingboxConfig)。
class ProxyCoreEngine implements VpnEngine {
  static const MethodChannel _control = MethodChannel('mirrorspeed/singbox');
  static const EventChannel  _stage   = EventChannel('mirrorspeed/singbox/stage');

  @override
  EngineKind get kind => EngineKind.singbox;

  @override
  Future<void> initialize() async {
    await _control.invokeMethod('initialize');
  }

  @override
  Stream<VpnStage> get stageStream =>
      _stage.receiveBroadcastStream().map(_mapStage);

  @override
  Future<VpnStage> stage() async {
    final s = await _control.invokeMethod<String>('stage');
    return _mapStageName(s ?? 'disconnected');
  }

  @override
  Future<void> start(EngineStartParams p) async {
    final cfg = p.singboxConfig;
    if (cfg == null) {
      throw ArgumentError('ProxyCoreEngine.start 需要 singboxConfig');
    }
    // 原生侧接收完整 sing-box 配置 JSON 字符串,建立 VpnService 并交给 libbox。
    await _control.invokeMethod('start', {'config': jsonEncode(cfg)});
  }

  @override
  Future<void> stop() async {
    await _control.invokeMethod('stop');
  }

  @override
  Future<List<int>> transferRxTx() async {
    final r = await _control.invokeMethod<List<dynamic>>('transferRxTx');
    if (r == null || r.length < 2) return const [-1, -1];
    return [(r[0] as num).toInt(), (r[1] as num).toInt()];
  }

  // 原生 stage 事件(String)→ VpnStage
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
