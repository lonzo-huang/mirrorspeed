/// AmneziaWG Flutter plugin — drop-in replacement for wireguard_flutter.
///
/// Usage:
///   await AmneziaWG.instance.initialize(interfaceName: 'awg0');
///   AmneziaWG.instance.vpnStageSnapshot.listen((stage) { ... });
///   await AmneziaWG.instance.startVpn(
///     serverAddress:            'vpn.example.com:PORT',
///     wgQuickConfig:            awgConfigString,   // includes Jc/Jmin/… params
///     providerBundleIdentifier: 'com.yourapp.tunnel',
///   );
///   await AmneziaWG.instance.stopVpn();
library amneziawg_flutter;

export 'src/awg_stage.dart';
export 'src/awg_platform_interface.dart' show AmneziawgFlutterInterface;

import 'src/awg_platform_interface.dart';

class AmneziaWG {
  AmneziaWG._();
  static final AmneziaWG instance = AmneziaWG._();

  Stream<VpnStage> get vpnStageSnapshot =>
      AmneziawgFlutterInterface.instance.vpnStageSnapshot;

  Future<void> initialize({required String interfaceName}) =>
      AmneziawgFlutterInterface.instance.initialize(interfaceName: interfaceName);

  Future<void> startVpn({
    required String serverAddress,
    required String wgQuickConfig,
    required String providerBundleIdentifier,
  }) =>
      AmneziawgFlutterInterface.instance.startVpn(
        serverAddress:            serverAddress,
        wgQuickConfig:            wgQuickConfig,
        providerBundleIdentifier: providerBundleIdentifier,
      );

  Future<void> stopVpn() => AmneziawgFlutterInterface.instance.stopVpn();

  Future<void> refreshStage() =>
      AmneziawgFlutterInterface.instance.refreshStage();

  Future<VpnStage> stage() => AmneziawgFlutterInterface.instance.stage();
}
