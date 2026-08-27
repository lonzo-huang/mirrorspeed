import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'vpn_engine.dart';

/// Windows 上的 sing-box 运行器：用官方 `sing-box.exe` 子进程 + wintun 网卡。
/// sing-box.exe 自行管理 tun，无需像 Android 那样写 VpnService。
///
/// 依赖（随 Windows 包一起分发，见 windows/ CMake 复制规则）：
///   - sing-box.exe（Windows amd64，https://github.com/SagerNet/sing-box/releases）
///   - wintun.dll （https://www.wintun.net/）
/// 两者放在应用 exe 同目录。创建 tun 需要管理员权限（app 清单已 requireAdministrator）。
class SingboxWindowsRunner {
  Process? _proc;
  VpnStage _stage = VpnStage.disconnected;
  final _stageCtrl = StreamController<VpnStage>.broadcast();
  bool _userStopping = false;
  bool _retriedNoV6 = false;
  final List<String> _tail = [];   // 最近若干行输出，仅用于判断 IPv6 FATAL 以便降级重试

  Stream<VpnStage> get stageStream => _stageCtrl.stream;
  VpnStage get stage => _stage;

  void _setStage(VpnStage s) {
    _stage = s;
    if (!_stageCtrl.isClosed) _stageCtrl.add(s);
  }

  /// 与应用 exe 同目录下的 sing-box.exe。
  String _exePath() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir\\sing-box.exe';
  }

  void _pushTail(String line) {
    _tail.add(line);
    if (_tail.length > 40) _tail.removeAt(0);
  }

  /// 去掉 tun inbound 里的 IPv6 地址（含 ':' 的条目）——用于「设 v6 地址 FATAL」时
  /// 降级为纯 IPv4 重试（IPv6 被禁用的机器上设 v6 地址会让 sing-box 起不来）。
  String _stripIpv6(String configJson) {
    try {
      final cfg = jsonDecode(configJson) as Map<String, dynamic>;
      final inbounds = cfg['inbounds'];
      if (inbounds is List) {
        for (final ib in inbounds) {
          if (ib is Map && ib['address'] is List) {
            ib['address'] = (ib['address'] as List)
                .where((a) => !a.toString().contains(':')).toList();
          }
        }
      }
      return jsonEncode(cfg);
    } catch (_) {
      return configJson;
    }
  }

  Future<void> start(String configJson) async {
    await stop();
    _userStopping = false;
    _retriedNoV6 = false;
    _tail.clear();
    await _launch(configJson);
  }

  Future<void> _launch(String configJson) async {
    _setStage(VpnStage.connecting);
    try {
      final support = await getApplicationSupportDirectory();
      final cfgPath = '${support.path}\\singbox-config.json';
      await File(cfgPath).writeAsString(configJson);

      final exe = _exePath();
      if (!File(exe).existsSync()) {
        _setStage(VpnStage.disconnected);
        throw StateError('sing-box.exe 未找到：$exe');
      }
      // -D 指定工作目录（缓存/geo 资源），--disable-color 便于解析日志。
      // ENABLE_DEPRECATED_LEGACY_DNS_SERVERS：sing-box 1.12+ 把旧版 DNS 服务器格式
      // 标为 FATAL，缺此变量 sing-box.exe 解析配置即退出。
      _proc = await Process.start(
        exe,
        ['run', '-c', cfgPath, '-D', support.path, '--disable-color'],
        environment: {'ENABLE_DEPRECATED_LEGACY_DNS_SERVERS': 'true'},
        mode: ProcessStartMode.normal,
      );

      void onLine(String line) {
        _pushTail(line);
        if (_stage == VpnStage.connecting && line.toLowerCase().contains('started')) {
          _setStage(VpnStage.connected);
        }
      }
      _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
      _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);

      _proc!.exitCode.then((code) {
        _proc = null;
        // IPv6 被禁用的机器上设 tun 的 v6 地址会 FATAL；自动去掉 v6 重试一次，保证能连上。
        final tailStr = _tail.join('\n').toLowerCase();
        final ipv6Fatal = tailStr.contains('ipv6 address') ||
            (tailStr.contains('tun') && tailStr.contains('element not found'));
        if (!_userStopping && ipv6Fatal && !_retriedNoV6) {
          _retriedNoV6 = true;
          _tail.clear();
          _launch(_stripIpv6(configJson));
          return;
        }
        _setStage(VpnStage.disconnected);
      });

      // 兜底：6 秒内没读到 started 但进程仍在，则乐观置为已连接（tun 通常已建立）。
      Future.delayed(const Duration(seconds: 6), () {
        if (_proc != null && _stage == VpnStage.connecting) _setStage(VpnStage.connected);
      });
    } catch (e) {
      _setStage(VpnStage.disconnected);
      rethrow;
    }
  }

  Future<void> stop() async {
    final p = _proc;
    _proc = null;
    _userStopping = true;
    if (p != null) {
      _setStage(VpnStage.disconnecting);
      p.kill();                // 终止 sing-box.exe，wintun 网卡随进程退出而移除
      try { await p.exitCode.timeout(const Duration(seconds: 4)); } catch (_) {}
    }
    _setStage(VpnStage.disconnected);
  }
}
