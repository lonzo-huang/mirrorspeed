import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

/// 分应用代理配置（智能模式黑白名单）。
/// - white(白名单)：只有名单内 App 走 VPN，其余直连。默认。
/// - black(黑名单)：名单内 App 直连，其余走 VPN。
/// 持久化在 SharedPreferences，连接时由 VpnProvider 注入 wg 配置
/// (IncludedApplications / ExcludedApplications)。
class AppProxyStore {
  static const _kEnabled = 'app_proxy_enabled';
  static const _kMode    = 'app_proxy_mode';   // 'white' | 'black'
  static const _kPkgs    = 'app_proxy_pkgs';
  static const _kInit    = 'app_proxy_inited';

  /// 默认海外 App 白名单包名（首次默认勾选，走 VPN）。
  static const List<String> defaultOverseas = [
    'com.google.android.youtube',
    'com.google.android.apps.youtube.music',
    'com.google.android.gm',
    'com.google.android.googlequicksearchbox',
    'com.google.android.apps.maps',
    'com.android.vending',                 // Google Play
    'com.google.android.apps.translate',
    'com.instagram.android',
    'com.facebook.katana',
    'com.facebook.orca',
    'com.whatsapp',
    'org.telegram.messenger',
    'com.twitter.android',
    'com.x.android',
    'com.zhiliaoapp.musically',            // TikTok 国际版
    'com.netflix.mediaclient',
    'com.spotify.music',
    'com.snapchat.android',
    'com.pinterest',
    'com.reddit.frontpage',
    'com.discord',
    'com.linkedin.android',
    'tv.twitch.android.app',
    'com.microsoft.office.outlook',
    'com.medium.reader',
    'org.mozilla.firefox',
    'com.brave.browser',
    'com.android.chrome',                  // Chrome：海外浏览常用，默认走 VPN
  ];

  /// 启用状态。Android 默认开；桌面默认**关**（opt-in）——桌面分应用是新功能，
  /// 且默认名单为空，若误开白名单会导致「只有名单内进程走 VPN」，默认关最安全。
  static Future<bool> loadEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? Platform.isAndroid;

  static Future<String> loadMode() async =>
      (await SharedPreferences.getInstance()).getString(_kMode) ?? 'white';

  /// 桌面进程名判定：形如 xxx.exe（不含安卓包名的点号命名，如 com.google.xxx）。
  static bool _isExe(String s) => s.toLowerCase().endsWith('.exe');

  /// 已选名单。Android 存包名、桌面存进程名(如 chrome.exe)。
  /// 首次(未初始化)：Android 返回默认海外白名单；桌面返回空(opt-in，用户自行添加进程)。
  /// 桌面额外过滤：只保留 .exe 进程名，剔除历史遗留的安卓包名——否则白名单里混入
  /// 安卓包名会让 sing-box 白名单永不匹配任何进程 → final=direct → VPN 变摆设。
  static Future<Set<String>> loadPkgs() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kInit) ?? false)) {
      return Platform.isAndroid ? defaultOverseas.toSet() : <String>{};
    }
    final list = p.getStringList(_kPkgs) ?? const <String>[];
    if (!Platform.isAndroid) return list.where(_isExe).toSet();
    return list.toSet();
  }

  static Future<void> save({required bool enabled, required String mode, required Set<String> pkgs}) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, enabled);
    await p.setString(_kMode, mode);
    await p.setStringList(_kPkgs, pkgs.toList());
    await p.setBool(_kInit, true);
  }
}
