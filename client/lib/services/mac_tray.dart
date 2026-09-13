import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import '../models/free_node.dart';
import '../models/server_config.dart';
import '../providers/auth_provider.dart';
import '../providers/shared_node_provider.dart';
import '../providers/vpn_provider.dart';

/// macOS 菜单栏（托盘）桥接。**仅 macOS 生效**，其它平台所有方法直接返回。
///
/// 原生侧在 macos/Runner/TrayController.swift：
///   Dart → 原生 `update`（状态 + 优质节点列表，用于重建菜单）
///   原生 → Dart `connect` {id: 节点 id 或 "auto"} / `disconnect` / `show`
class MacTray {
  MacTray._();
  static final MacTray instance = MacTray._();

  static const _ch = MethodChannel('mirrorspeed/tray');

  static bool get supported => !kIsWeb && Platform.isMacOS;

  AuthProvider? _auth;
  VpnProvider? _vpn;
  SharedNodeProvider? _shared;
  String? _lastPayload;

  /// App 启动时接上 provider；两者变化时自动刷新菜单。
  void attach({
    required AuthProvider auth,
    required VpnProvider vpn,
    required SharedNodeProvider shared,
  }) {
    if (!supported || _vpn != null) return;
    _auth = auth;
    _vpn = vpn;
    _shared = shared;
    _ch.setMethodCallHandler(_onNativeCall);
    auth.addListener(sync);
    vpn.addListener(sync);
    shared.addListener(sync);
    sync();
  }

  /// 菜单里展示的免费节点数量（按延迟取最快的若干个；全部列表在主窗口里选）。
  static const _kFreeInMenu = 10;

  /// 把当前状态和节点列表推给菜单栏（内容没变则不推）。
  Future<void> sync() async {
    if (!supported) return;
    final vpn = _vpn, auth = _auth;
    if (vpn == null || auth == null) return;

    final servers = auth.displayServers.where((s) => !s.isDisplayOnly).toList();

    // 免费节点：按延迟升序取最快的 N 个（不可达的排最后、不进菜单）。
    final shared = _shared;
    final freeAll = (shared?.nodes ?? <FreeNode>[])
        .where((n) => (shared?.latencyOf(n) ?? -1) >= 0)
        .toList()
      ..sort((a, b) => (shared!.latencyOf(a) ?? 999999)
          .compareTo(shared.latencyOf(b) ?? 999999));
    final free = freeAll.take(_kFreeInMenu).toList();

    // 免费节点连着时，整体状态以它为准（两条隧道互斥，同一时刻只有一条）。
    final sharedStage = shared?.stage;
    final sharedBusy = sharedStage == VpnStage.connecting;
    final sharedOn = shared?.isConnected ?? false;

    final status = sharedOn
        ? 'connected'
        : sharedBusy
            ? 'connecting'
            : switch (vpn.status) {
                VpnStatus.connected     => 'connected',
                VpnStatus.connecting    => 'connecting',
                VpnStatus.disconnecting => 'disconnecting',
                _                       => 'disconnected',
              };

    final payload = <String, dynamic>{
      'status': status,
      // 当前生效的是哪条隧道：premium / free / none（菜单按此打勾、换图标）
      'kind': sharedOn || sharedBusy
          ? 'free'
          : (vpn.status == VpnStatus.connected || vpn.status == VpnStatus.connecting)
              ? 'premium'
              : 'none',
      'activeId':   sharedOn ? shared?.active?.fingerprint : vpn.activeServer?.id,
      'activeName': sharedOn ? shared?.active?.name : vpn.activeServer?.displayName,
      'autoSelect': vpn.autoSelect,
      'servers': [
        for (final s in servers)
          {
            'id': s.id,
            'name': s.displayName,
            'flag': s.flagEmoji,
            'latency': s.latencyMs ?? -1,
          }
      ],
      'freeNodes': [
        for (final n in free)
          {
            'id': n.fingerprint,
            'name': n.name,
            'latency': shared?.latencyOf(n) ?? -1,
          }
      ],
      // 用量：连接时长 + 实时速率；免费用户另给今日剩余时长。
      'elapsed': vpn.isConnected ? vpn.elapsedFormatted : null,
      'speed': status == 'connected' ? '↓ ${vpn.downloadSpeedStr}  ↑ ${vpn.uploadSpeedStr}' : null,
      'trialRemaining': vpn.isFreeTrial ? vpn.trialRemainingFormatted : null,
      'quotaExceeded': vpn.quotaExceeded,
    };
    final encoded = payload.toString();
    if (encoded == _lastPayload) return;
    _lastPayload = encoded;
    try {
      await _ch.invokeMethod('update', payload);
    } catch (e) {
      debugPrint('[TRAY] update failed: $e');
    }
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final vpn = _vpn, auth = _auth;
    if (vpn == null || auth == null) return null;
    switch (call.method) {
      case 'connectFree':
        final id = (call.arguments as Map?)?['id'] as String?;
        final shared = _shared;
        if (shared == null || id == null) return null;
        for (final n in shared.nodes) {
          if (n.fingerprint == id) {
            await shared.connect(n);
            break;
          }
        }
        return null;
      case 'connect':
        final id = (call.arguments as Map?)?['id'] as String?;
        final servers = auth.displayServers.where((s) => !s.isDisplayOnly).toList();
        if (id == 'auto') {
          await vpn.setAutoSelect(true);
          await vpn.connectAuto(servers);
        } else {
          ServerConfig? target;
          for (final s in servers) {
            if (s.id == id) { target = s; break; }
          }
          if (target != null) {
            await vpn.setAutoSelect(false);
            await vpn.connect(target);
          }
        }
        return null;
      case 'disconnect':
        await _shared?.disconnect();
        await vpn.disconnect();
        return null;
      case 'show':
        // 窗口由原生侧唤起，这里只确保菜单内容是最新的。
        _lastPayload = null;
        await sync();
        return null;
    }
    return null;
  }
}
