import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../env.dart';
import '../models/server_config.dart';

class ApiService {
  static ApiService get instance => _instance;
  static final ApiService _instance = ApiService._();
  ApiService._();

  // 优质节点配置（含 wg 私钥）本地缓存：存加密的 secure storage，不落明文。
  // 作用：冷启动先读缓存秒出节点列表；当 www.mirrorspeed.com（引导域名）被墙/超时
  // 导致刷新失败时，用户仍能看到并连接上次的优质节点，打破「要拉节点先连 VPN、
  // 要连 VPN 先拉节点」的死锁。
  final _secure = const FlutterSecureStorage();
  static const _kConfigCacheKey = 'cached_configs_body_v1';

  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ── 引导域名 failover ─────────────────────────────────────────
  // 主域名被墙（DNS 污染 / SNI 阻断 / 连接被重置）时自动切到兜底域名。
  // 只在【连接级失败】时换域名；收到任何 HTTP 响应（含 4xx/5xx）即认定该
  // 域名可达并记住，本会话后续请求优先用它（避免每次从头试）。
  String? _activeBase;
  static const Duration _kNetTimeout = Duration(seconds: 12);

  List<String> get _bases {
    final seen = <String>{};
    final out  = <String>[];
    if (_activeBase != null && seen.add(_activeBase!)) out.add(_activeBase!);
    for (final b in kApiBases) { if (seen.add(b)) out.add(b); }
    return out;
  }

  Future<http.Response> _send(
      Future<http.Response> Function(String base) run) async {
    Object? lastErr;
    for (final base in _bases) {
      try {
        final res = await run(base).timeout(_kNetTimeout);
        _activeBase = base;               // 记住可达域名
        return res;
      } on TimeoutException catch (e)     { lastErr = e; }
        on SocketException catch (e)      { lastErr = e; }
        on HandshakeException catch (e)   { lastErr = e; }
        on http.ClientException catch (e) { lastErr = e; }  // 连接被重置等
      if (kDebugMode) debugPrint('引导域名 $base 连接失败，尝试下一个: $lastErr');
    }
    throw ApiException('无法连接服务器（已尝试全部线路）');
  }

  Future<http.Response> _get(String path) =>
      _send((base) => http.get(Uri.parse('$base$path'), headers: _headers));

  Future<http.Response> _post(String path, Object body) =>
      _send((base) => http.post(Uri.parse('$base$path'),
          headers: _headers, body: jsonEncode(body)));

  // ── 设备注册/获取 ────────────────────────────────────────────
  Future<Map<String, dynamic>> registerDevice({
    required String platform,
    required String deviceName,
    String? cachedDeviceId,          // UUID cached from previous registration
    String? fingerprint,             // 硬件指纹：区分同账号的不同终端
  }) async {
    final body = <String, dynamic>{
      'platform':    platform,
      'device_name': deviceName,
    };
    if (cachedDeviceId != null) body['device_id'] = cachedDeviceId;
    if (fingerprint != null)    body['fingerprint'] = fingerprint;

    final res = await _post('/api/mobile/device', body);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body) as Map<String, dynamic>;
    throw ApiException(
      err['error'] ?? '注册设备失败 (${res.statusCode})',
      code: err['code'] as String?,
      data: err,
    );
  }

  // ── 邀请信息 ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> fetchReferralInfo() async {
    final res = await _get('/api/mobile/referral');
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '获取邀请信息失败 (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── 绑定邀请码 ────────────────────────────────────────────────
  Future<void> applyReferralCode(String code) async {
    final res = await _post('/api/mobile/referral', {'code': code});
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '绑定邀请码失败 (${res.statusCode})');
    }
  }

  // ── 拉取 WireGuard 配置 ──────────────────────────────────────
  Future<List<DeviceInfo>> fetchConfigs({ String? deviceId }) async {
    final qs = (deviceId != null && deviceId.isNotEmpty)
        ? '?device_id=${Uri.encodeQueryComponent(deviceId)}'
        : '';
    final res = await _get('/api/mobile/configs$qs');
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '获取配置失败 (${res.statusCode})');
    }
    final body    = jsonDecode(res.body) as Map<String, dynamic>;
    final devices = body['devices'] as List;
    final parsed  = devices.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>)).toList();
    // 仅缓存「有设备配置」的成功响应；空列表不覆盖旧缓存（避免误清空可用节点）。
    if (devices.isNotEmpty) {
      try {
        await _secure.write(key: _kConfigCacheKey, value: res.body);
      } catch (e) {
        if (kDebugMode) debugPrint('缓存优质配置失败: $e');
      }
    }
    return parsed;
  }

  /// 读取上次成功拉取的优质节点配置缓存（冷启动/网络不可用时使用）。
  /// 解析失败或无缓存时返回空列表，调用方据此回退到正常刷新流程。
  Future<List<DeviceInfo>> loadCachedConfigs() async {
    try {
      final raw = await _secure.read(key: _kConfigCacheKey);
      if (raw == null || raw.isEmpty) return [];
      final body    = jsonDecode(raw) as Map<String, dynamic>;
      final devices = body['devices'] as List;
      return devices
          .map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('读取优质配置缓存失败: $e');
      return [];
    }
  }

  /// 登出时清除优质配置缓存（不保留上一账号的节点/私钥）。
  Future<void> clearCachedConfigs() async {
    try {
      await _secure.delete(key: _kConfigCacheKey);
    } catch (_) {/* ignore */}
  }

  // ── 按需建 peer（连接前 / 节点列表预热）──────────────────────
  // serverIds 为空 = 全部活跃节点（列表预热）；给定 = 仅这些（连接前单台）。
  // 失败不抛异常（尽力而为），返回是否至少成功一个。
  Future<bool> ensurePeer({ String? deviceId, List<String>? serverIds }) async {
    if (_token == null) return false;
    try {
      final res = await _post('/api/mobile/ensure-peer', {
        if (deviceId != null)  'device_id':  deviceId,
        if (serverIds != null) 'server_ids': serverIds,
      });
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['ensured'] as int? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  // ── 公开节点列表（无需登录，仅展示用，不含密钥/配置）#1 ────────────
  Future<List<ServerConfig>> fetchPublicServers() async {
    try {
      final res = await _get('/api/servers');
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['servers'] as List?) ?? [];
      return list
          .map((s) => ServerConfig.fromPublicJson(s as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 最新版本（用于更新提示）#2 ────────────────────────────────────
  // 返回 {version, url}；失败返回 null。
  Future<Map<String, String?>?> fetchLatestVersion() async {
    try {
      final res = await _get('/api/releases/latest');
      if (res.statusCode != 200) return null;
      final b = jsonDecode(res.body) as Map<String, dynamic>;
      final v = b['version'] as String?;
      if (v == null) return null;
      return {
        'version':     v,
        'url':         'https://www.mirrorspeed.com/download',
        'min_version': b['min_version'] as String?,   // 低于此版本强制更新
      };
    } catch (_) {
      return null;
    }
  }

  // ── 全局通告（运营下发，公开）#2 ──────────────────────────────────
  // 返回 {id,title,body,level}；无通告返回 null。
  Future<Map<String, dynamic>?> fetchAnnouncement() async {
    try {
      final res = await _get('/api/announcement');
      if (res.statusCode != 200) return null;
      final b = jsonDecode(res.body) as Map<String, dynamic>;
      if (b['announcement'] == null) return null;
      return b['announcement'] as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

class ApiException implements Exception {
  final String message;
  final String? code;                 // 结构化错误码，如 'DEVICE_LIMIT'
  final Map<String, dynamic>? data;   // 附带字段，如 {max, is_paid}
  ApiException(this.message, {this.code, this.data});
  @override String toString() => message;
}
