import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const String _portalBase = 'https://www.mirrorspeed.com';

/// 打开门户网页。若 App 已登录，则通过 `/auth/app-bridge` 携带当前 Supabase 会话
/// （放在 URL fragment `#` 里，不会发送到服务器），浏览器端据此建立同一登录态，
/// 用户无需在网页重复登录；未登录则直接打开目标页。
///
/// [path] 站内相对路径，如 '/dashboard/billing'、'/pricing'。
Future<void> openPortal(String path) async {
  final session = Supabase.instance.client.auth.currentSession;
  final rt = session?.refreshToken ?? '';
  final Uri uri;
  if (session != null && rt.isNotEmpty) {
    final frag = 'at=${Uri.encodeComponent(session.accessToken)}'
        '&rt=${Uri.encodeComponent(rt)}'
        '&next=${Uri.encodeComponent(path)}';
    uri = Uri.parse('$_portalBase/auth/app-bridge#$frag');
  } else {
    uri = Uri.parse('$_portalBase$path');
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
