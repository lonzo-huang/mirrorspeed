import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'awg_stage.dart';
import '../amneziawg_flutter_method_channel.dart';

export 'awg_stage.dart';

abstract class AmneziawgFlutterInterface extends PlatformInterface {
  AmneziawgFlutterInterface() : super(token: _token);
  static final Object _token = Object();

  static AmneziawgFlutterInterface _instance = AmneziawgFlutterMethodChannel();
  static AmneziawgFlutterInterface get instance => _instance;
  static set instance(AmneziawgFlutterInterface i) {
    PlatformInterface.verifyToken(i, _token);
    _instance = i;
  }

  /// Stream of VPN tunnel state changes.
  Stream<VpnStage> get vpnStageSnapshot;

  /// Initialize the tunnel (must be called once on startup).
  Future<void> initialize({required String interfaceName});

  /// Bring the tunnel up.
  Future<void> startVpn({
    required String serverAddress,
    required String wgQuickConfig,
    required String providerBundleIdentifier,
  });

  /// Bring the tunnel down.
  Future<void> stopVpn();

  /// Force a state refresh from native side.
  Future<void> refreshStage();

  /// Query current stage.
  Future<VpnStage> stage();
}
