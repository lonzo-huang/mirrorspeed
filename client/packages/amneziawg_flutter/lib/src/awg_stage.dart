/// VPN tunnel states — mirrors wireguard_flutter's VpnStage for drop-in compatibility.
enum VpnStage {
  /// Preparing VPN permission / tunnel bring-up
  prepare,
  /// Actively connecting
  connecting,
  /// Tunnel is up and passing traffic
  connected,
  /// Graceful teardown in progress
  disconnecting,
  /// Tunnel is fully down
  disconnected,
  /// Unexpected error state
  error,
  /// Unknown / initial state
  noConnection,
  ;

  static VpnStage fromString(String? s) => switch (s?.toLowerCase()) {
    'prepare'       => VpnStage.prepare,
    'connecting'    => VpnStage.connecting,
    'connected'     => VpnStage.connected,
    'disconnecting' => VpnStage.disconnecting,
    'disconnected'  => VpnStage.disconnected,
    'error'         => VpnStage.error,
    _               => VpnStage.noConnection,
  };
}
