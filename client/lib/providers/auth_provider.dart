import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../models/server_config.dart';
import '../env.dart';

enum AuthStatus { loading, unauthenticated, authenticated, noSubscription }

class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final _storage  = const FlutterSecureStorage();

  AuthStatus          _status    = AuthStatus.loading;
  String?             _deviceId;
  String?             _deviceLabel;
  List<DeviceInfo>    _configs   = [];
  String?             _error;

  AuthStatus       get status      => _status;
  String?          get deviceId    => _deviceId;
  String?          get deviceLabel => _deviceLabel;
  List<DeviceInfo> get configs          => _configs;
  List<ServerConfig> get servers        => _configs.isNotEmpty ? _configs.first.servers : [];
  String?          get error            => _error;

  // ── 流量额度（取第一个设备，通常用户只有一台设备）──────────
  int?  get dailyQuotaBytes  => _configs.isNotEmpty ? _configs.first.dailyQuotaBytes  : null;
  int   get dailyBytesUsed   => _configs.isNotEmpty ? _configs.first.dailyBytesUsed   : 0;
  bool  get isSuspended      => _configs.isNotEmpty ? _configs.first.isSuspended      : false;
  double? get usageRatio     => _configs.isNotEmpty ? _configs.first.usageRatio       : null;
  bool get isLoggedIn => _supabase.auth.currentSession != null;

  AuthProvider() {
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session != null) {
        _onLoggedIn();
      } else {
        _status = AuthStatus.unauthenticated;
        _configs = [];
        notifyListeners();
      }
    });
  }

  // ── 初始化（app 启动时调用）──────────────────────────────────
  Future<void> initialize() async {
    if (_supabase.auth.currentSession != null) {
      await _onLoggedIn();
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  // ── 登录后流程 ───────────────────────────────────────────────
  Future<void> _onLoggedIn() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      // 自动注册/获取设备
      // Pass cached device_id (if any) so the server can recognise returning devices
      // without relying on a device_fingerprint column that doesn't exist in the schema.
      final cachedId   = await _storage.read(key: 'device_id');
      final platform   = _getPlatform();
      final deviceName = await _getDeviceName();

      final info = await ApiService.instance.registerDevice(
        platform:        platform,
        deviceName:      deviceName,
        cachedDeviceId:  cachedId,
      );
      _deviceId    = info['device_id']    as String?;
      _deviceLabel = info['device_label'] as String?;

      // 缓存 device_id
      await _storage.write(key: 'device_id', value: _deviceId);

      // 拉取所有节点配置
      await refreshConfigs();

      _status = AuthStatus.authenticated;
    } on ApiException catch (e) {
      if (e.message.contains('订阅')) {
        _status = AuthStatus.noSubscription;
      } else {
        _error  = e.message;
        _status = AuthStatus.authenticated; // 仍然已登录，只是配置获取失败
      }
    } catch (e) {
      _error  = e.toString();
      _status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  // ── 刷新配置 ─────────────────────────────────────────────────
  Future<void> refreshConfigs() async {
    final devId = _deviceId ?? await _storage.read(key: 'device_id');
    try {
      _configs = await ApiService.instance.fetchConfigs(deviceId: devId);
      _error   = null;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // ── 登出 ─────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _storage.delete(key: 'device_id');
    _deviceId = null; _configs = [];
    _status   = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── 发送 Magic Link ──────────────────────────────────────────
  Future<void> signInWithEmail(String email) async {
    await _supabase.auth.signInWithOtp(
      email:           email,
      emailRedirectTo: kAuthCallbackUrl,
    );
  }

  // ── OAuth 登录 ───────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kAuthCallbackUrl,
    );
  }

  Future<void> signInWithMicrosoft() async {
    await _supabase.auth.signInWithOAuth(
      OAuthProvider.azure,
      redirectTo: kAuthCallbackUrl,
    );
  }

  // ── 工具方法 ─────────────────────────────────────────────────
  Future<String> _getDeviceFingerprint() async {
    // 先尝试从安全存储读取缓存的指纹
    final cached = await _storage.read(key: 'device_fingerprint');
    if (cached != null) return cached;

    final info = DeviceInfoPlugin();
    String fp;
    if (Platform.isAndroid) {
      final d = await info.androidInfo;
      fp = d.id; // Android hardware device ID
    } else if (Platform.isIOS) {
      final d = await info.iosInfo;
      fp = d.identifierForVendor ?? 'ios_unknown_${DateTime.now().millisecondsSinceEpoch}';
    } else if (Platform.isWindows) {
      final d = await info.windowsInfo;
      fp = d.deviceId;
    } else {
      fp = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
    await _storage.write(key: 'device_fingerprint', value: fp);
    return fp;
  }

  String _getPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS)     return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS)   return 'macos';
    return 'linux';
  }

  Future<String> _getDeviceName() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final d = await info.androidInfo;
      return '${d.brand} ${d.model}';
    } else if (Platform.isIOS) {
      final d = await info.iosInfo;
      return d.name;
    } else if (Platform.isWindows) {
      final d = await info.windowsInfo;
      return d.computerName;
    }
    return 'My Device';
  }
}
