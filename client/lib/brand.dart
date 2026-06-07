import 'dart:ui';

/// 双壳品牌抽象（单 App，运行时按设备语言切壳）。
///
/// 背景 / 设计说明（给后续开发者 / AI）：
/// - 本 App 是**单一安装包**(applicationId=com.mirrorspeed.vpn)，上架 Google Play 用一个 listing，
///   以减少维护成本。原来的 `global` / `cn` 两个 flavor 已**合并**。
/// - "壳"由**运行时设备语言**决定，不再用编译期 `--dart-define=APP_FLAVOR`：
///     · 中文环境  → 镜速加速器（合规：面向中文用户**不出现 "VPN" 字样**）
///     · 其它语言  → MirrorSpeed VPN（正常显示）
/// - 启动器图标名称由 Android 资源限定符自动切换（res/values 与 res/values-zh 的 app_name），
///   与本类无关；本类负责 **App 内**的文案 / 功能开关。
/// - 未来两壳的功能可能分化（不同特性 / 不同合规策略）——一切差异都应集中到本类，
///   通过新增 getter 扩展，**不要**把 `Brand.isZh` 判断散落到各处。
class Brand {
  Brand._();

  /// 设备语言是否中文。
  static bool get isZh =>
      PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'zh';

  /// App 内显示的产品名称。
  static String get appName => isZh ? '镜速加速器' : 'MirrorSpeed VPN';

  /// 合规：中文壳不显示 "VPN" 字样。
  static bool get hideVpnWording => isZh;

  /// 是否展示「智能/全局」路由切换（中文壳特性）。
  static bool get showSmartRouting => isZh;
}
