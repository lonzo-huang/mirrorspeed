import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Pure-Dart UDP ↔ WebSocket relay for WireGuard-over-WebSocket fallback.
///
/// Architecture:
///   WireGuard UDP → 127.0.0.1:localPort → [this relay] → WSS
///     → Nginx /secure-tunnel/ → wstunnel v9 → WireGuard server
///
/// Protocol (wstunnel v9.7+):
///   - Path:    /v1/events
///   - Header:  Sec-WebSocket-Protocol: v1, authorization.bearer.{JWT}
///   - JWT secret (hardcoded in wstunnel source): "champignonfrais"
///   - JWT payload: {"id":"{uuid}","p":{"Udp":{"timeout":null}},"r":"host","rp":port}
///
/// Usage:
///   final relay = WsRelayService();
///   final port  = await relay.start('wss://vpn.example.com/secure-tunnel', 39666);
///   // configure WireGuard Endpoint = 127.0.0.1:port
///   await relay.stop();
class WsRelayService {
  WebSocket?          _ws;
  RawDatagramSocket?  _udp;
  StreamSubscription? _wsSub;
  StreamSubscription? _udpSub;
  int?                _localPort;

  int?  get localPort => _localPort;
  bool  get isRunning => _localPort != null;

  // wstunnel v9 hardcoded JWT secret (from wstunnel source: src/tunnel/mod.rs)
  static const _jwtSecret = 'champignonfrais';

  /// Connect to wstunnel server via WebSocket and start relaying.
  ///
  /// [wsBaseUrl] should be the base URL including Nginx path prefix,
  ///   e.g. 'wss://vpn.example.com/secure-tunnel'
  /// [wgPort] is the WireGuard UDP port on the server (e.g. 39666)
  ///
  /// Returns the local UDP port that WireGuard should use as its Endpoint.
  Future<int> start(String wsBaseUrl, int wgPort) async {
    await stop(); // clean up any previous relay

    // ── 1. Bind loopback UDP on a random OS-assigned port ────────────
    _udp       = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _udp!.port;
    debugPrint('[WsRelay] UDP bound on 127.0.0.1:$_localPort');

    // ── 2. Build JWT and connect to wstunnel server ──────────────────
    // wstunnel v9.7+ uses /v1/events path with JWT in Sec-WebSocket-Protocol
    final wsUrl  = '$wsBaseUrl/v1/events';
    final jwt    = _makeJwt('127.0.0.1', wgPort);
    final proto1 = 'v1';
    final proto2 = 'authorization.bearer.$jwt';

    debugPrint('[WsRelay] Connecting → $wsUrl');
    _ws = await WebSocket.connect(
      wsUrl,
      protocols: [proto1, proto2],
    ).timeout(const Duration(seconds: 10));
    debugPrint('[WsRelay] WebSocket connected');

    // WireGuard source address recorded from first packet
    InternetAddress? wgAddr;
    int?             wgSrcPort;

    // ── WireGuard → WebSocket ─────────────────────────────────────────
    _udpSub = _udp!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final dg = _udp!.receive();
        if (dg != null) {
          wgAddr    = dg.address;
          wgSrcPort = dg.port;
          try { _ws?.add(dg.data); } catch (_) {}
        }
      }
    });

    // ── WebSocket → WireGuard ─────────────────────────────────────────
    _wsSub = _ws!.listen(
      (dynamic data) {
        if (wgAddr == null || wgSrcPort == null) return;
        final bytes = data is Uint8List
            ? data
            : Uint8List.fromList(data as List<int>);
        try { _udp?.send(bytes, wgAddr!, wgSrcPort!); } catch (_) {}
      },
      onError: (Object e) => debugPrint('[WsRelay] WS error: $e'),
      onDone:  ()         => debugPrint('[WsRelay] WS closed by server'),
      cancelOnError: false,
    );

    return _localPort!;
  }

  Future<void> stop() async {
    _localPort = null;
    await _udpSub?.cancel();
    await _wsSub?.cancel();
    try { await _ws?.close(WebSocketStatus.normalClosure); } catch (_) {}
    _udp?.close();
    _ws = null; _udp = null; _wsSub = null; _udpSub = null;
    debugPrint('[WsRelay] stopped');
  }

  // ── JWT generation ────────────────────────────────────────────────
  /// Generate a wstunnel v9.7+ JWT signed with the hardcoded secret.
  static String _makeJwt(String remoteHost, int remotePort) {
    // Header: {"typ":"JWT","alg":"HS256"}
    final header = _b64url(utf8.encode('{"typ":"JWT","alg":"HS256"}'));

    // Payload: {"id":"{uuid}","p":{"Udp":{"timeout":null}},"r":"host","rp":port}
    final payload = _b64url(utf8.encode(json.encode({
      'id': _uuidv4(),
      'p':  {'Udp': {'timeout': null}},
      'r':  remoteHost,
      'rp': remotePort,
    })));

    // HMAC-SHA256 signature with secret "champignonfrais"
    final msg    = utf8.encode('$header.$payload');
    final key    = utf8.encode(_jwtSecret);
    final digest = Hmac(sha256, key).convert(msg);
    final sig    = _b64url(digest.bytes);

    return '$header.$payload.$sig';
  }

  /// URL-safe base64 without padding.
  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// Generate a random UUID v4.
  static String _uuidv4() {
    final rng   = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    return '${h(bytes[0])}${h(bytes[1])}${h(bytes[2])}${h(bytes[3])}'
        '-${h(bytes[4])}${h(bytes[5])}'
        '-${h(bytes[6])}${h(bytes[7])}'
        '-${h(bytes[8])}${h(bytes[9])}'
        '-${h(bytes[10])}${h(bytes[11])}${h(bytes[12])}'
        '${h(bytes[13])}${h(bytes[14])}${h(bytes[15])}';
  }
}
