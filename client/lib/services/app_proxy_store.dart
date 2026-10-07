import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

/// 分应用代理配置。
/// - white(代理名单)：只有名单内 App 走 VPN，其余直连。
/// - black(直连名单)：名单内 App 直连，其余 App 进隧道(再按智能/全局+地区分流)。【默认】
/// 默认 = 直连名单 + 空名单 = 所有 App 都走智能分流(新装 App 自动纳入)，用户仅在"某 App
/// 不想走 VPN"时把它加进直连名单。不再预置境外白名单(有了 airlane 分流后，预置白名单
/// 反而会把名单外的境外访问漏成直连)。
/// 持久化在 SharedPreferences，连接时由 VpnProvider 注入 wg 配置
/// (IncludedApplications / ExcludedApplications)。
class AppProxyStore {
  static const _kMode    = 'app_proxy_mode';   // 'white' | 'black'
  static const _kPkgs    = 'app_proxy_pkgs';
  static const _kInit    = 'app_proxy_inited';

  /// 当前平台是否支持分应用代理。iOS/macOS 的 NEPacketTunnelProvider 不支持按 App
  /// 分流（需 MDM 下发的 per-app VPN），故 Apple 上隐藏入口、走全局隧道。
  static bool get supported => Platform.isAndroid || Platform.isWindows;

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

  static Future<String> loadMode() async =>
      (await SharedPreferences.getInstance()).getString(_kMode) ?? 'black';

  /// 桌面进程名判定：形如 xxx.exe（不含安卓包名的点号命名，如 com.google.xxx）。
  static bool _isExe(String s) => s.toLowerCase().endsWith('.exe');

  /// 已选名单。Android 存包名、桌面存进程名(如 chrome.exe)。
  /// 首次(未初始化)：返回空名单(配默认的"直连名单"模式 = 所有 App 都走智能分流)。
  /// 桌面额外过滤：只保留 .exe 进程名，剔除历史遗留的安卓包名——否则名单里混入
  /// 安卓包名会让 sing-box 名单永不匹配任何进程。
  static Future<Set<String>> loadPkgs() async {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool(_kInit) ?? false)) {
      return <String>{};
    }
    final list = p.getStringList(_kPkgs) ?? const <String>[];
    if (!Platform.isAndroid) return list.where(_isExe).toSet();
    return list.toSet();
  }

  static Future<void> save({required String mode, required Set<String> pkgs}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMode, mode);
    await p.setStringList(_kPkgs, pkgs.toList());
    await p.setBool(_kInit, true);
  }
}
