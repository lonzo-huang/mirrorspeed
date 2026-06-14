import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/ad_service.dart';
import '../models/server_config.dart';
import '../env.dart';
import '../version.dart';
import '../brand.dart';

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

  // 公开节点（未登录展示）+ 版本/通告（#1 #2）
  List<ServerConfig>     _publicServers = [];
  String?                _latestVersion;
  Map<String, dynamic>?  _announcement;

  AuthStatus       get status      => _status;
  String?          get deviceId    => _deviceId;
  String?          get deviceLabel => _deviceLabel;
  List<DeviceInfo> get configs          => _configs;
  List<ServerConfig> get servers        => _configs.isNotEmpty ? _configs.first.servers : [];
  /// 列表展示用：已登录用真实节点；未登录用公开节点（仅展示，连接前需登录）。
  List<ServerConfig> get displayServers => servers.isNotEmpty ? servers : _publicServers;
  String?          get error            => _error;
  DateTime?        get subExpiresAt     => _subExpiresAt;

  // ── 版本/通告（#2）────────────────────────────────────────────
  String?               get latestVersion => _latestVersion;
  Map<String, dynamic>? get announcement  => _announcement;
  /// 线上版本是否比当前 App 新（简单 semver 比较）。
  bool get updateAvailable =>
      _latestVersion != null && _isNewer(_latestVersion!, kAppVersion);

  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .replaceAll(RegExp(r'^v'), '')
        .split('+').first
        .split('.')
        .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '0') ?? 0)
        .toList();
    final r = parse(remote), l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  /// Days until subscription expires. null = no subscription or already expired.
  int? get daysUntilExpiry {
    if (_subExpiresAt == null) return null;
    final days = _subExpiresAt!.difference(DateTime.now()).inDays;
    return days >= 0 ? days : null;
  }

  // ── 流量额度（取第一个设备，通常用户只有一台设备）──────────
  int?  get dailyQuotaBytes   => _configs.isNotEmpty ? _configs.first.dailyQuotaBytes   : null;
  int?  get dailyQuotaSeconds => _configs.isNotEmpty ? _configs.first.dailyQuotaSeconds : null;
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
    _loadAppMeta();   // 公开节点 + 版本 + 通告（无需登录，后台拉取）
    if (_supabase.auth.currentSession != null) {
      await _onLoggedIn();
    } else {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
    }
  }

  // 拉取公开节点列表 + 最新版本 + 全局通告（#1 #2）。失败均静默。
  Future<void> _loadAppMeta() async {
    final results = await Future.wait([
      ApiService.instance.fetchPublicServers(),
      ApiService.instance.fetchLatestVersion(),
      ApiService.instance.fetchAnnouncement(),
    ]);
    _publicServers = results[0] as List<ServerConfig>;
    final ver      = results[1] as Map<String, String?>?;
    _latestVersion = ver?['version'];
    _announcement  = results[2] as Map<String, dynamic>?;
    notifyListeners();
  }

  // ── 登录后流程 ───────────────────────────────────────────────
  Future<void> _onLoggedIn() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      // 自动注册/获取设备
      // Pass cached device_id (if any) so the server can recognise returning devices
      // without relying on a device_fingerprint column that doesn't exist in the schema.
      final cachedId    = await _storage.read(key: 'device_id');
      final platform    = _getPlatform();
      final deviceName  = await _getDeviceName();
      final fingerprint = await _getDeviceFingerprint();   // 硬件指纹，区分不同终端

      final info = await ApiService.instance.registerDevice(
        platform:        platform,
        deviceName:      deviceName,
        cachedDeviceId:  cachedId,
        fingerprint:     fingerprint,
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
      if (e.code == 'DEVICE_LIMIT') {
        final max    = (e.data?['max'] as num?)?.toInt() ?? 2;
        final isPaid = e.data?['is_paid'] == true;
        _error  = _deviceLimitMessage(max: max, isPaid: isPaid);
        _status = AuthStatus.authenticated;
      } else if (e.message.contains('订阅')) {
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
    // 缓存会员标记：付费用户(无每日额度)下次冷启动可跳过开屏广告（#2）。
    await _persistMemberFlag();
    notifyListeners();
  }

  // 付费会员 = 没有每日时长/流量额度。缓存供启动时（auth 未就绪前）判断。
  Future<void> _persistMemberFlag() async {
    final paid = _configs.isNotEmpty &&
        _configs.first.dailyQuotaSeconds == null &&
        _configs.first.dailyQuotaBytes == null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_member', paid);
    // 运行时立即生效：会员 → 关停并丢弃所有广告（修复会员偶尔仍看到开屏，#3）。
    AdService.instance.setEnabled(!paid);
  }

  // ── 登出 ─────────────────────────────────────────────────────
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _storage.delete(key: 'device_id');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_member', false);
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

  // ── 邮箱 + 密码 登录 ──────────────────────────────────────────
  Future<void> signInWithPassword(String email, String password) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      // 成功后 onAuthStateChange 自动触发 _onLoggedIn()
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('credentials')) {
        throw Exception('邮箱或密码错误');
      } else if (msg.contains('not confirmed') || msg.contains('confirm')) {
        throw Exception('邮箱尚未确认，请先到邮箱点击确认链接');
      } else {
        throw Exception('登录失败：${e.message}');
      }
    }
  }

  // ── 邮箱 + 密码 注册 ──────────────────────────────────────────
  // 注册后通常需到邮箱点确认链接才能登录（取决于后台是否开启邮箱确认）。
  Future<void> signUpWithPassword(String email, String password) async {
    try {
      await _supabase.auth.signUp(
        email:           email,
        password:        password,
        emailRedirectTo: kAuthCallbackUrl,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already') || msg.contains('registered')) {
        throw Exception('该邮箱已注册，请直接登录');
      } else if (msg.contains('weak') || msg.contains('password')) {
        throw Exception('密码太弱，至少 6 位');
      } else {
        throw Exception('注册失败：${e.message}');
      }
    }
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
  // 设备数量超限提示：跟随系统语言；免费用户额外引导升级到收费版（更多终端）。
  String _deviceLimitMessage({required int max, required bool isPaid}) {
    if (isPaid) {
      return tr(
        '设备数量已达上限（$max 台），请在网页端删除旧设备后再试。',
        'Device limit reached ($max devices). Remove an old device on the web portal to add a new one.',
      );
    }
    return tr(
      '免费版最多 $max 台设备。升级到会员可同时使用 5 台设备，请在网页端删除旧设备或升级会员。',
      'The free plan allows up to $max devices. Upgrade to Premium to use 5 devices at once, or remove an old device on the web portal.',
    );
  }

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
