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
  DateTime?           _subExpiresAt;

  AuthStatus       get status      => _status;
  String?          get deviceId    => _deviceId;
  String?          get deviceLabel => _deviceLabel;
  List<DeviceInfo> get configs          => _configs;
  List<ServerConfig> get servers        => _configs.isNotEmpty ? _configs.first.servers : [];
  String?          get error            => _error;
  DateTime?        get subExpiresAt     => _subExpiresAt;

  /// Days until subscription expires. null = no subscription or already expired.
  int? get daysUntilExpiry {
    if (_subExpiresAt == null) return null;
    final days = _subExpiresAt!.difference(DateTime.now()).inDays;
    return days >= 0 ? days : null;
  }

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

      // 拉取订阅到期时间（用于到期提醒）
      await _fetchSubscriptionExpiry();

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

  // ── 订阅到期时间 ─────────────────────────────────────────────
  Future<void> _fetchSubscriptionExpiry() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final res = await _supabase
          .from('subscriptions')
          .select('expires_at')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      if (res != null && res['expires_at'] != null) {
        _subExpiresAt = DateTime.parse(res['expires_at'] as String).toLocal();
      }
    } catch (_) {
      // non-fatal
    }
  }

  // ── 刷新配置 ─────────────────────────────────────────────────
  Future<void> refreshConfigs() async {
    final devId = _deviceId ?? await _storage.read(key: 'device_id');
    try {
      _configs = await ApiService.instance.fetchConfigs(deviceId: devId);
      _error   = null;
    } on ApiException catch (e) {
      // 如果是 401 Unauthorized，先刷新 token 再重试一次
      if (e.message.contains('401') || e.message.contains('Unauthorized')) {
        try {
          await _supabase.auth.refreshSession();
          _configs = await ApiService.instance.fetchConfigs(deviceId: devId);
          _error   = null;
        } catch (_) {
          _error = e.message;
        }
      } else {
        _error = e.message;
      }
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

  // ── 发送 OTP 验证码 ───────────────────────────────────────────
  Future<void> signInWithEmail(String email) async {
    try {
      await _supabase.auth.signInWithOtp(
        email:            email,
        shouldCreateUser: true,
        emailRedirectTo:  kAuthCallbackUrl,
      );
    } on AuthException catch (e) {
      // Map common Supabase error codes to friendlier Chinese messages
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many')) {
        throw Exception('发送太频繁，请稍后再试（每小时限 5 次）');
      } else if (msg.contains('invalid email') || msg.contains('email')) {
        throw Exception('邮箱地址无效，请检查后重试');
      } else if (msg.contains('server') || msg.contains('500')) {
        throw Exception('服务器暂时出错，请稍等片刻再重试');
      } else {
        throw Exception('发送失败：${e.message}');
      }
    }
  }

  // ── 验证 OTP 验证码 ──────────────────────────────────────────
  Future<void> verifyOtp(String email, String token) async {
    await _supabase.auth.verifyOTP(
      email: email,
      token: token,
      type:  OtpType.email,
    );
    // 验证成功后 onAuthStateChange 会自动触发 _onLoggedIn()
  }

  // ── OAuth 登录 ───────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kAuthCallbackUrl,
      );
    } on AuthException catch (e) {
      throw Exception('Google 登录失败：${e.message}');
    }
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
