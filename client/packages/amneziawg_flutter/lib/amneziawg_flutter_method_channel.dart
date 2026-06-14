import 'dart:async';
import 'package:flutter/services.dart';
import 'src/awg_platform_interface.dart';
import 'src/awg_stage.dart';

/// Default MethodChannel implementation — used on Android, iOS, Windows.
class AmneziawgFlutterMethodChannel extends AmneziawgFlutterInterface {
  static const _kControl = 'com.amneziawg.flutter/awgcontrol';
  static const _kStage   = 'com.amneziawg.flutter/awgstage';

  final _controlChannel = const MethodChannel(_kControl);
  final _stageChannel   = const EventChannel(_kStage);

  @override
  Stream<VpnStage> get vpnStageSnapshot => _stageChannel
      .receiveBroadcastStream()
      .map((e) => VpnStage.fromString(e as String?));

  @override
  Future<void> initialize({required String interfaceName, String? description}) =>
      _controlChannel.invokeMethod('initialize', {
        // 适配器描述（本地化）；win32ServiceName 仍用接口名作为服务名。
        'localizedDescription': description ?? interfaceName,
        'win32ServiceName':     interfaceName,
      });

  @override
  Future<void> startVpn({
    required String serverAddress,
    required String wgQuickConfig,
    required String providerBundleIdentifier,
  }) =>
      _controlChannel.invokeMethod('start', {
        'serverAddress':            serverAddress,
        'wgQuickConfig':            wgQuickConfig,
        'providerBundleIdentifier': providerBundleIdentifier,
      });

  @override
  Future<void> stopVpn() => _controlChannel.invokeMethod('stop');

  @override
  Future<void> refreshStage() => _controlChannel.invokeMethod('stage');

  @override
  Future<VpnStage> stage() async {
    final s = await _controlChannel.invokeMethod<String>('stage');
    return VpnStage.fromString(s);
  }

  @override
  Future<int> transfer() async {
    try {
      final v = await _controlChannel.invokeMethod<int>('transfer');
      return v ?? -1;
    } catch (_) {
      // MissingPluginException on platforms without an impl (e.g. iOS) → -1
      return -1;
    }
  }

  @override
  Future<List<int>> transferRxTx() async {
    try {
      final v = await _controlChannel.invokeListMethod<int>('transferRxTx');
      if (v != null && v.length >= 2) return v;
    } catch (_) { /* 平台未实现 → 回退 */ }
    // 回退：用合并值（仅当 down 显示，up=0）
    final t = await transfer();
    return t < 0 ? const [-1, -1] : [t, 0];
  }
}
