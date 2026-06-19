import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../env.dart';
import '../models/server_config.dart';

class ApiService {
  static ApiService get instance => _instance;
  static final ApiService _instance = ApiService._();
  ApiService._();

  String? get _token => Supabase.instance.client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
    'Content-Type':  'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

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

    final res = await http.post(
      Uri.parse('$kApiBase/api/mobile/device'),
      headers: _headers,
      body: jsonEncode(body),
    );
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
    final res = await http.get(
      Uri.parse('$kApiBase/api/mobile/referral'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '获取邀请信息失败 (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── 绑定邀请码 ────────────────────────────────────────────────
  Future<void> applyReferralCode(String code) async {
    final res = await http.post(
      Uri.parse('$kApiBase/api/mobile/referral'),
      headers: _headers,
      body: jsonEncode({'code': code}),
    );
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '绑定邀请码失败 (${res.statusCode})');
    }
  }

  // ── 拉取 WireGuard 配置 ──────────────────────────────────────
  Future<List<DeviceInfo>> fetchConfigs({ String? deviceId }) async {
    final uri = Uri.parse('$kApiBase/api/mobile/configs')
        .replace(queryParameters: deviceId != null ? { 'device_id': deviceId } : null);

    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw ApiException(err['error'] ?? '获取配置失败 (${res.statusCode})');
    }
    final body    = jsonDecode(res.body) as Map<String, dynamic>;
    final devices = body['devices'] as List;
    return devices.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>)).toList();
  }

  // ── 按需建 peer（连接前 / 节点列表预热）──────────────────────
  // serverIds 为空 = 全部活跃节点（列表预热）；给定 = 仅这些（连接前单台）。
  // 失败不抛异常（尽力而为），返回是否至少成功一个。
  Future<bool> ensurePeer({ String? deviceId, List<String>? serverIds }) async {
    if (_token == null) return false;
    try {
      final res = await http.post(
        Uri.parse('$kApiBase/api/mobile/ensure-peer'),
        headers: _headers,
        body: jsonEncode({
          if (deviceId != null)        'device_id':  deviceId,
          if (serverIds != null)       'server_ids': serverIds,
        }),
      ).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['ensured'] as int? ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  // ── 公开节点列表（无需登录，仅展示用，不含密钥/配置）#1 ────────────
  Future<List<ServerConfig>> fetchPublicServers() async {
    final res = await http.get(Uri.parse('$kApiBase/api/servers'));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['servers'] as List?) ?? [];
    return list
        .map((s) => ServerConfig.fromPublicJson(s as Map<String, dynamic>))
        .toList();
  }

  // ── 最新版本（用于更新提示）#2 ────────────────────────────────────
  // 返回 {version, url}；失败返回 null。
  Future<Map<String, String?>?> fetchLatestVersion() async {
    try {
      final res = await http.get(Uri.parse('$kApiBase/api/releases/latest'));
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
      final res = await http.get(Uri.parse('$kApiBase/api/announcement'));
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
