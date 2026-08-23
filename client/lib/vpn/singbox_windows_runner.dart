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
/// 两者放在应用 exe 同目录。创建 tun 需要管理员权限（首启右键“以管理员运行”）。
class SingboxWindowsRunner {
  Process? _proc;
  VpnStage _stage = VpnStage.disconnected;
  final _stageCtrl = StreamController<VpnStage>.broadcast();

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

  Future<void> start(String configJson) async {
    await stop();
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
      //（{tag,address,detour}，SingboxConfig 目前用的就是这种）标为 FATAL，缺此变量
      // sing-box.exe 会在解析配置时直接退出 → Windows 免费节点“全部连不上”。
      // Android 的 libbox 构建不强制该检查，故仅桌面需要。（1.14 将彻底移除旧格式，
      // 届时需把 SingboxConfig 的 dns.servers 迁移到新格式。）
      _proc = await Process.start(
        exe,
        ['run', '-c', cfgPath, '-D', support.path, '--disable-color'],
        environment: {'ENABLE_DEPRECATED_LEGACY_DNS_SERVERS': 'true'},
        mode: ProcessStartMode.normal,
      );
      _proc!.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        // sing-box 启动完成日志：出现 "sing-box started" 视为已连接。
        if (line.contains('sing-box started') || line.contains('started')) {
          if (_stage == VpnStage.connecting) _setStage(VpnStage.connected);
        }
      });
      _proc!.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.toLowerCase().contains('started')) {
          if (_stage == VpnStage.connecting) _setStage(VpnStage.connected);
        }
      });
      _proc!.exitCode.then((_) {
        _proc = null;
        _setStage(VpnStage.disconnected);
      });
      // 兜底：若 3 秒内没读到 started 日志，仍乐观置为已连接（tun 已建立）。
      Future.delayed(const Duration(seconds: 3), () {
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
    if (p != null) {
      _setStage(VpnStage.disconnecting);
      p.kill();                // 终止 sing-box.exe，wintun 网卡随进程退出而移除
      try { await p.exitCode.timeout(const Duration(seconds: 4)); } catch (_) {}
    }
    _setStage(VpnStage.disconnected);
  }
}
