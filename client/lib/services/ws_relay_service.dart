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
/// Reconnect:
///   If the WebSocket closes unexpectedly, the relay automatically reconnects.
///   The local UDP port stays the same, so AWG doesn't need to be restarted.
class WsRelayService {
  RawDatagramSocket?  _udp;
  StreamSubscription? _udpSub;
  int?                _localPort;

  // Current WebSocket (replaced on reconnect)
  WebSocket?          _ws;
  StreamSubscription? _wsSub;

  // Saved for reconnection
  String? _wsUrl;
  String? _jwtToken;
  bool    _stopped = true;

  // Reconnect back-off
  int _reconnectAttempt = 0;

  int?  get localPort => _localPort;
  bool  get isRunning => !_stopped && _localPort != null;

  // wstunnel v9 hardcoded JWT secret
  static const _jwtSecret = 'champignonfrais';

  /// Connect to wstunnel server via WebSocket and start relaying.
  ///
  /// [wsBaseUrl] e.g. 'wss://vpn.example.com/secure-tunnel'
  /// [wgPort] AWG internal port on the server (e.g. 51820)
  ///
  /// Returns the local UDP port to use as the WireGuard Endpoint.
  Future<int> start(String wsBaseUrl, int wgPort) async {
    await stop(); // clean up previous relay
    _stopped = false;
    _reconnectAttempt = 0;

    // Bind loopback UDP — port is fixed for the lifetime of this relay session
    _udp       = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _udp!.port;
    debugPrint('[WsRelay] UDP bound on 127.0.0.1:$_localPort');

    // Save connection params for reconnect
    _wsUrl    = '$wsBaseUrl/v1/events';
    _jwtToken = _makeJwt('127.0.0.1', wgPort);

    // WireGuard → WebSocket (drain ALL queued datagrams per event)
    InternetAddress? wgAddr;
    int?             wgSrcPort;

    _udpSub = _udp!.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;
      // Drain every queued datagram — one RawSocketEvent.read may cover several
      Datagram? dg;
      while ((dg = _udp?.receive()) != null) {
        wgAddr    = dg!.address;
        wgSrcPort = dg.port;
        final ws = _ws;
        if (ws != null && ws.readyState == WebSocket.open) {
          try { ws.add(dg.data); } catch (e) {
            debugPrint('[WsRelay] UDP→WS send error: $e');
          }
        }
      }
    });

    // Initial WebSocket connection (reconnect logic lives in _connectWs)
    await _connectWs(
      onData: (Uint8List bytes) {
        final addr = wgAddr;
        final port = wgSrcPort;
        if (addr == null || port == null) return;
        try { _udp?.send(bytes, addr, port); } catch (e) {
          debugPrint('[WsRelay] WS→UDP send error: $e');
        }
      },
    );

    // _localPort can only be null here if stop() was called concurrently
    // (e.g. a second _switchToRelay call racing with this one).
    final port = _localPort;
    if (port == null) throw StateError('WsRelay stopped during startup');
    return port;
  }

  /// (Re-)establish the WebSocket connection.
  Future<void> _connectWs({required void Function(Uint8List) onData}) async {
    if (_stopped) return;

    final url   = _wsUrl!;
    final jwt   = _jwtToken!;
    final http  = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        debugPrint('[WsRelay] TLS cert accepted for $host');
        return true;
      };

    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        url,
        protocols: ['v1', 'authorization.bearer.$jwt'],
        customClient: http,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[WsRelay] connect failed: $e');
      _scheduleReconnect(onData: onData);
      return;
    }

    _ws = ws;
    _reconnectAttempt = 0;
    debugPrint('[WsRelay] WebSocket connected (attempt $_reconnectAttempt)');

    _wsSub?.cancel();
    _wsSub = ws.listen(
      (dynamic data) {
        final bytes = data is Uint8List
            ? data
            : Uint8List.fromList(data as List<int>);
        onData(bytes);
      },
      onError: (Object e) => debugPrint('[WsRelay] WS error: $e'),
      onDone: () {
        debugPrint('[WsRelay] WS closed by server');
        if (!_stopped) _scheduleReconnect(onData: onData);
      },
      cancelOnError: false,
    );
  }

  /// Reconnect with exponential back-off (max 8 s).
  void _scheduleReconnect({required void Function(Uint8List) onData}) {
    if (_stopped) return;
    _reconnectAttempt++;
    final delaySecs = min(1 << (_reconnectAttempt - 1), 8); // 1, 2, 4, 8, 8, …
    debugPrint('[WsRelay] reconnecting in ${delaySecs}s (attempt $_reconnectAttempt)');
    Future.delayed(Duration(seconds: delaySecs), () => _connectWs(onData: onData));
  }

  Future<void> stop() async {
    _stopped = true;
    _wsUrl   = null;
    _jwtToken = null;
    _localPort = null;
    await _udpSub?.cancel();
    await _wsSub?.cancel();
    try { await _ws?.close(WebSocketStatus.normalClosure); } catch (_) {}
    _udp?.close();
    _ws = null; _udp = null; _wsSub = null; _udpSub = null;
    debugPrint('[WsRelay] stopped');
  }

  // ── JWT generation ────────────────────────────────────────────────
  static String _makeJwt(String remoteHost, int remotePort) {
    final header  = _b64url(utf8.encode('{"typ":"JWT","alg":"HS256"}'));
    final payload = _b64url(utf8.encode(json.encode({
      'id': _uuidv4(),
      'p':  {'Udp': {'timeout': null}},
      'r':  remoteHost,
      'rp': remotePort,
    })));
    final msg     = utf8.encode('$header.$payload');
    final key     = utf8.encode(_jwtSecret);
    final digest  = Hmac(sha256, key).convert(msg);
    return '$header.$payload.${_b64url(digest.bytes)}';
  }

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _uuidv4() {
    final rng   = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    return '${h(bytes[0])}${h(bytes[1])}${h(bytes[2])}${h(bytes[3])}'
        '-${h(bytes[4])}${h(bytes[5])}'
        '-${h(bytes[6])}${h(bytes[7])}'
        '-${h(bytes[8])}${h(bytes[9])}'
        '-${h(bytes[10])}${h(bytes[11])}${h(bytes[12])}'
        '${h(bytes[13])}${h(bytes[14])}${h(bytes[15])}';
  }
}
