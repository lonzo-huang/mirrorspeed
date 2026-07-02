import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'env.dart';
import 'app.dart';
import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url:         kSupabaseUrl,
    anonKey:     kSupabaseAnon,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // ── OAuth deep-link callback (Windows desktop) ──────────────────────────
  // On Android/iOS, supabase_flutter handles the deep link automatically.
  // On Windows, we need to intercept the mirrorspeed:// URL ourselves and
  // pass it to Supabase so it can complete the OAuth token exchange.
  if (!kIsWeb && Platform.isWindows) {
    // 便携版(ZIP)无安装器，需自注册 mirrorspeed:// 协议到当前用户注册表(HKCU，免管理员)，
    // 否则浏览器完成 Google 登录后的 mirrorspeed://login-callback 无法唤起本 App。
    await _registerWindowsUrlScheme();
    final appLinks = AppLinks();

    // App launched cold via deep link (e.g. second instance forwarded URL)
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleOAuthCallback(initialUri);
      }
    } catch (_) {}

    // App already running — incoming deep link (WM_COPYDATA from 2nd instance)
    appLinks.uriLinkStream.listen((uri) async {
      try {
        await _handleOAuthCallback(uri);
      } catch (_) {}
    });
  }

  // ── 广告初始化（仅 Android/iOS）+ 开屏广告（可跳过，不阻塞启动）──────
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // 付费会员不展示任何广告（#2）。用上次缓存的会员标记，启动即判断。
    final prefs = await SharedPreferences.getInstance();
    final isMember = prefs.getBool('is_member') ?? false;
    await AdService.instance.initialize(enabled: !isMember);
    if (!isMember) {
      // 给开屏广告 ~2.5s 加载时间；加载到就展示，没加载到就静默跳过。
      Future.delayed(const Duration(milliseconds: 2500),
          AdService.instance.showAppOpenIfAvailable);
    }
  }

  runApp(const MirrorSpeedApp());
}

Future<void> _handleOAuthCallback(Uri uri) async {
  final uriStr = uri.toString();
  // Only handle auth callback URLs
  if (!uriStr.contains('login-callback') &&
      !uriStr.contains('access_token') &&
      !uriStr.contains('code=')) return;

  try {
    await Supabase.instance.client.auth.getSessionFromUrl(uri);
  } catch (e) {
    debugPrint('[OAuth] getSessionFromUrl error: $e');
  }
}

// Windows：把 mirrorspeed:// 协议注册到 HKCU\Software\Classes（免管理员、幂等）。
// 让浏览器完成 OAuth 后能唤起本 App 回传会话。
Future<void> _registerWindowsUrlScheme() async {
  try {
    final exe = Platform.resolvedExecutable;
    const base = r'HKCU\Software\Classes\mirrorspeed';
    await Process.run('reg', ['add', base, '/ve', '/d', 'URL:MirrorSpeed', '/f']);
    await Process.run('reg', ['add', base, '/v', 'URL Protocol', '/d', '', '/f']);
    await Process.run('reg', ['add', '$base\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
  } catch (e) {
    debugPrint('[Win] URL scheme register failed: $e');
  }
}
