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

  /// sing-box 完整运行日志的落盘路径（诊断用）。
  String? logPath;
  /// 最近一次失败的可读信息（含日志尾），供上层提示。
  String? lastError;
  final List<String> _tail = [];   // 保留最近若干行日志

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

  IOSink? _logSink;
  void _log(String line) {
    _tail.add(line);
    if (_tail.length > 60) _tail.removeAt(0);
    try { _logSink?.writeln(line); } catch (_) {}
  }

  Future<void> start(String configJson) async {
    await stop();
    _userStopping = false;
    lastError = null;
    _tail.clear();
    _setStage(VpnStage.connecting);
    try {
      final support = await getApplicationSupportDirectory();
      final cfgPath = '${support.path}\\singbox-config.json';
      await File(cfgPath).writeAsString(configJson);

      // 打开日志文件（覆盖），把 sing-box 全部输出落盘，便于诊断“连上却不通”。
      logPath = '${support.path}\\singbox.log';
      try {
        _logSink = File(logPath!).openWrite();
        _log('=== MirrorSpeed sing-box run @ ${DateTime.now()} ===');
        _log('exe=${_exePath()}  cfg=$cfgPath  workdir=${support.path}');
      } catch (_) {}

      final exe = _exePath();
      if (!File(exe).existsSync()) {
        _setStage(VpnStage.disconnected);
        throw StateError('sing-box.exe 未找到：$exe');
      }
      final started = DateTime.now();
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
        _log(line);
        final low = line.toLowerCase();
        if (_stage == VpnStage.connecting &&
            (line.contains('sing-box started') || low.contains('started'))) {
          _setStage(VpnStage.connected);
        }
      }
      _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
      _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);

      _proc!.exitCode.then((code) {
        final ranMs = DateTime.now().difference(started).inMilliseconds;
        _proc = null;
        try { _logSink?.writeln('=== exit code=$code after ${ranMs}ms ==='); } catch (_) {}
        try { _logSink?.flush(); _logSink?.close(); } catch (_) {}
        _logSink = null;
        // 非用户主动停止、且很快就退出的 = 启动失败。记录日志尾供上层提示。
        if (!_userStopping) {
          lastError = 'sing-box 已退出(code=$code)。日志：$logPath\n'
              '${_tail.length > 12 ? _tail.sublist(_tail.length - 12).join('\n') : _tail.join('\n')}';
        }
        _setStage(VpnStage.disconnected);
      });

      // 兜底：6 秒内没读到 started 但进程仍在，则乐观置为已连接（tun 通常已建立）。
      Future.delayed(const Duration(seconds: 6), () {
        if (_proc != null && _stage == VpnStage.connecting) _setStage(VpnStage.connected);
      });
    } catch (e) {
      lastError = '$e';
      try { _logSink?.flush(); _logSink?.close(); } catch (_) {}
      _logSink = null;
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
    try { _logSink?.flush(); _logSink?.close(); } catch (_) {}
    _logSink = null;
    _setStage(VpnStage.disconnected);
  }
}
