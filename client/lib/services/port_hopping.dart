/// HMAC-SHA256 port hopping service.
///
/// The server keeps three consecutive hour-windows open simultaneously
/// (current − 1, current, current + 1), so mild clock skew is tolerated.
///
/// Port formula (matches server-side awg-port-rotate.sh):
///   window = floor(unix_epoch_seconds / 3600)          ← hours since epoch
///   port   = 30000 + HMAC-SHA256(secret, BE_uint64(window))[0..3] % 20000
///
/// The message is the window number encoded as a big-endian 8-byte uint64,
/// exactly matching the Python struct.pack('>Q', window) on the server.
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
    // Hours since Unix epoch — matches server: W_CUR=$(( $(date -u +%s) / 3600 ))
    final nowMs  = DateTime.now().toUtc().millisecondsSinceEpoch;
    final window = (nowMs ~/ 3600000) + hourOffset;
    return _hmacPort(portSecret, window);
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

  /// Compute port = 30000 + first-4-bytes-big-endian-of-HMAC % 20000.
  ///
  /// [window] is hours since Unix epoch. The HMAC message is [window] encoded
  /// as a big-endian 8-byte uint64 — matching server: struct.pack('>Q', window)
  int _hmacPort(String secret, int window) {
    final key = utf8.encode(secret);

    // Big-endian uint64 encoding of window (8 bytes)
    final buf = ByteData(8);
    // Dart int is 64-bit on native; shift arithmetic is safe for window ≈ 5e5
    buf.setUint32(0, (window >> 32) & 0xFFFFFFFF, Endian.big);
    buf.setUint32(4,  window        & 0xFFFFFFFF, Endian.big);
    final msg = buf.buffer.asUint8List();

    final digest = Hmac(sha256, key).convert(msg);

    // Take first 4 bytes as big-endian uint32
    final bytes = Uint8List.fromList(digest.bytes.sublist(0, 4));
    final val   = (bytes[0] << 24) | (bytes[1] << 16) |
                  (bytes[2] << 8)  |  bytes[3];

    // Map to [30000, 49999]
    return 30000 + (val % 20000);
  }
}
