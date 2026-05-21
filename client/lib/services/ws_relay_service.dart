import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Pure-Dart UDP ↔ WebSocket relay for WireGuard-over-WebSocket fallback.
///
/// Architecture:
///   WireGuard UDP → 127.0.0.1:localPort → [this relay] → WSS
///     → Nginx /secure-tunnel/ → wstunnel → WireGuard server
///
/// Usage:
///   final relay = WsRelayService();
///   final port  = await relay.start('wss://vpn.example.com/secure-tunnel/udp/127.0.0.1/39666');
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

  /// Connect to [wsUrl] (wstunnel server via Nginx WSS proxy) and start relaying.
  /// Returns the local UDP port that WireGuard should use as its Endpoint.
  Future<int> start(String wsUrl) async {
    await stop(); // clean up any previous relay

    // ── 1. Bind loopback UDP on a random OS-assigned port ────────────
    _udp       = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _localPort = _udp!.port;
    debugPrint('[WsRelay] UDP bound on 127.0.0.1:$_localPort');

    // ── 2. Connect to wstunnel server via WebSocket (TLS) ────────────
    _ws = await WebSocket.connect(wsUrl)
        .timeout(const Duration(seconds: 10));
    debugPrint('[WsRelay] WebSocket connected → $wsUrl');

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
}
