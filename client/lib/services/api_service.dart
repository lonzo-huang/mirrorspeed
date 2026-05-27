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
  }) async {
    final body = <String, dynamic>{
      'platform':    platform,
      'device_name': deviceName,
    };
    if (cachedDeviceId != null) body['device_id'] = cachedDeviceId;

    final res = await http.post(
      Uri.parse('$kApiBase/api/mobile/device'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body);
    throw ApiException(err['error'] ?? '注册设备失败 (${res.statusCode})');
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
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override String toString() => message;
}
