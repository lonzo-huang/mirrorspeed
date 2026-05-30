/// HMAC-SHA256 port hopping service.
///
/// The server keeps three consecutive hour-windows open simultaneously
/// (current − 1, current, current + 1), so mild clock skew is tolerated.
///
/// Port formula (matches server-side 05-port-hopping.sh):
///   port = 30000 + HMAC-SHA256(portSecret, UTC_hour_string)[0..3] % 20000
///
/// The client tries the current hour first, then ±1 for resilience.
library port_hopping;

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class PortHoppingService {
  PortHoppingService._();
  static final PortHoppingService instance = PortHoppingService._();

  // ── Public API ────────────────────────────────────────────────────────────

  /// Compute the port for a given UTC hour window.
  ///
  /// [portSecret] is the shared HMAC secret (stored on server at
  ///   /etc/wireguard/.port-secret, returned by the VPN API).
  /// [hourOffset] is 0 (current), −1 (previous), +1 (next).
  int computePort(String portSecret, {int hourOffset = 0}) {
    final now        = DateTime.now().toUtc();
    final hourWindow = now.add(Duration(hours: hourOffset));
    // Format: "YYYY-MM-DD HH" — must match the server-side format
    final hourStr = _formatHour(hourWindow);
    return _hmacPort(portSecret, hourStr);
  }

  /// Return the three candidate ports to try in order: current, −1, +1.
  List<int> candidatePorts(String portSecret) => [
        computePort(portSecret, hourOffset: 0),
        computePort(portSecret, hourOffset: -1),
        computePort(portSecret, hourOffset: 1),
      ];

  /// Replace the port in an AWG/WireGuard config string.
  ///
  /// Matches lines like:
  ///   Endpoint = vpn.example.com:51820
  ///   Endpoint = 82.223.165.88:51820
  String rewriteEndpointPort(String wgConf, int port) {
    return wgConf.replaceAllMapped(
      RegExp(r'(Endpoint\s*=\s*\S+):(\d+)', caseSensitive: false),
      (m) => '${m.group(1)}:$port',
    );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Format DateTime as "YYYY-MM-DD HH" (zero-padded).
  String _formatHour(DateTime dt) {
    final y  = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d  = dt.day.toString().padLeft(2, '0');
    final h  = dt.hour.toString().padLeft(2, '0');
    return '$y-$mo-$d $h';
  }

  /// Compute port = 30000 + first-4-bytes-big-endian-of-HMAC % 20000.
  int _hmacPort(String secret, String message) {
    final key    = utf8.encode(secret);
    final msg    = utf8.encode(message);
    final hmac   = Hmac(sha256, key);
    final digest = hmac.convert(msg);

    // Take first 4 bytes as big-endian uint32
    final bytes = Uint8List.fromList(digest.bytes.sublist(0, 4));
    final val   = (bytes[0] << 24) | (bytes[1] << 16) |
                  (bytes[2] << 8)  |  bytes[3];

    // Map to [30000, 49999]
    return 30000 + (val % 20000);
  }
}
