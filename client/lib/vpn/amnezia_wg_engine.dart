import 'dart:io';
import 'package:amneziawg_flutter/amneziawg_flutter.dart';
import 'vpn_engine.dart';

/// AmneziaWG 引擎：把现有的 `AmneziaWG.instance` 调用包成 [VpnEngine]。
/// 用于「优质节点」（付费自建服务器）。行为与重构前完全一致。
class AmneziaWgEngine implements VpnEngine {
  @override
  EngineKind get kind => EngineKind.amneziawg;

  @override
  Future<void> initialize() => AmneziaWG.instance.initialize(
        interfaceName: 'mirrorspeed',
        description:    _adapterDescription(),
      );

  @override
  Stream<VpnStage> get stageStream => AmneziaWG.instance.vpnStageSnapshot;

  @override
  Future<VpnStage> stage() => AmneziaWG.instance.stage();

  @override
  Future<void> start(EngineStartParams p) => AmneziaWG.instance.startVpn(
        serverAddress:            p.serverAddress!,
        wgQuickConfig:            p.wgQuickConfig!,
        providerBundleIdentifier: p.providerBundle!,
      );

  @override
  Future<void> stop() => AmneziaWG.instance.stopVpn();

  @override
  Future<List<int>> transferRxTx() => AmneziaWG.instance.transferRxTx();

  // 网络适配器对外描述（Windows ipconfig / 网络连接里可见）。绝不暴露 WireGuard 字样。
  static String _adapterDescription() {
    final locale = Platform.localeName.toLowerCase();
    return locale.startsWith('zh') ? 'MirrorSpeed 加速隧道' : 'MirrorSpeed VPN';
  }
}
