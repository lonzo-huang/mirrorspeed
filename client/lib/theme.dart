import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 兼容旧代码的顶层常量（深色值；尚未适配主题的页面仍在用）───────────────
// 新代码请用 context.ms.<token>（见 MsColors）以支持明/暗切换。
const kBrand     = Color(0xFF35E0C0);  // 品牌薄荷绿（原 indigo 已弃用）
const kBrandDark = Color(0xFF12A594);
const kSuccess   = Color(0xFF34D07A);
const kDanger    = Color(0xFFEF4444);
const kSurface   = Color(0xFF16211F);
const kCard      = Color(0xFF16211F);
const kBg        = Color(0xFF0C1618);
const kPanel     = Color(0xFF16211F);
const kAccentOn  = Color(0xFF3EDC8C);  // 连接态绿
const kGold      = Color(0xFFE8C766);
const kMuted     = Color(0xFF8A9C98);

/// 语义化配色令牌（明/暗各一套）。新 UI 一律通过 `context.ms.xxx` 取色。
@immutable
class MsColors extends ThemeExtension<MsColors> {
  final Color bg;          // 页面背景
  final Color bgGradTop;   // 背景渐变顶（浅→深）
  final Color card;        // 卡片/面板
  final Color cardBorder;  // 卡片描边
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brand;       // 品牌薄荷绿（未连接强调 / 主页选中）
  final Color accentOn;    // 已连接绿（大圆环填充）
  final Color gold;        // 会员金
  final Color goldBannerBg;
  final Color danger;      // 红（时长用完）
  final Color divider;
  final Color navBg;       // 底部导航背景
  final Color pill;        // 顶部语言/主题小胶囊背景
  final Color ringTrack;   // 圆环底色

  const MsColors({
    required this.bg, required this.bgGradTop, required this.card,
    required this.cardBorder, required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.brand, required this.accentOn,
    required this.gold, required this.goldBannerBg, required this.danger,
    required this.divider, required this.navBg, required this.pill, required this.ringTrack,
  });

  static const dark = MsColors(
    bg:            Color(0xFF0B1517),
    bgGradTop:     Color(0xFF11201F),
    card:          Color(0xFF15201E),
    cardBorder:    Color(0x14FFFFFF),
    textPrimary:   Color(0xFFF2F7F5),
    textSecondary: Color(0xFF9DB2AD),
    textMuted:     Color(0xFF6C807B),
    brand:         Color(0xFF35E0C0),
    accentOn:      Color(0xFF3FDC8C),
    gold:          Color(0xFFE8C766),
    goldBannerBg:  Color(0xFF3A3320),
    danger:        Color(0xFFF06363),
    divider:       Color(0x14FFFFFF),
    navBg:         Color(0xFF0C1719),
    pill:          Color(0xFF17221F),
    ringTrack:     Color(0x1AFFFFFF),
  );

  static const light = MsColors(
    bg:            Color(0xFFE9F4EF),
    bgGradTop:     Color(0xFFF1F8F4),
    card:          Color(0xFFFFFFFF),
    cardBorder:    Color(0x0F0F2A22),
    textPrimary:   Color(0xFF10221D),
    textSecondary: Color(0xFF5C6E69),
    textMuted:     Color(0xFF8AA39C),
    brand:         Color(0xFF12A594),
    accentOn:      Color(0xFF1E9E5B),
    gold:          Color(0xFFB88A21),
    goldBannerBg:  Color(0xFFFBEFCF),
    danger:        Color(0xFFDC4B4B),
    divider:       Color(0x140F2A22),
    navBg:         Color(0xFFF4FAF7),
    pill:          Color(0xFFFFFFFF),
    ringTrack:     Color(0x14103A30),
  );

  @override
  MsColors copyWith({
    Color? bg, Color? bgGradTop, Color? card, Color? cardBorder, Color? textPrimary,
    Color? textSecondary, Color? textMuted, Color? brand, Color? accentOn, Color? gold,
    Color? goldBannerBg, Color? danger, Color? divider, Color? navBg, Color? pill, Color? ringTrack,
  }) => MsColors(
    bg: bg ?? this.bg, bgGradTop: bgGradTop ?? this.bgGradTop, card: card ?? this.card,
    cardBorder: cardBorder ?? this.cardBorder, textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary, textMuted: textMuted ?? this.textMuted,
    brand: brand ?? this.brand, accentOn: accentOn ?? this.accentOn, gold: gold ?? this.gold,
    goldBannerBg: goldBannerBg ?? this.goldBannerBg, danger: danger ?? this.danger,
    divider: divider ?? this.divider, navBg: navBg ?? this.navBg, pill: pill ?? this.pill,
    ringTrack: ringTrack ?? this.ringTrack,
  );

  @override
  MsColors lerp(ThemeExtension<MsColors>? other, double t) {
    if (other is! MsColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return MsColors(
      bg: c(bg, other.bg), bgGradTop: c(bgGradTop, other.bgGradTop), card: c(card, other.card),
      cardBorder: c(cardBorder, other.cardBorder), textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary), textMuted: c(textMuted, other.textMuted),
      brand: c(brand, other.brand), accentOn: c(accentOn, other.accentOn), gold: c(gold, other.gold),
      goldBannerBg: c(goldBannerBg, other.goldBannerBg), danger: c(danger, other.danger),
      divider: c(divider, other.divider), navBg: c(navBg, other.navBg), pill: c(pill, other.pill),
      ringTrack: c(ringTrack, other.ringTrack),
    );
  }
}

/// 便捷取色：`context.ms.brand`。
extension MsColorsX on BuildContext {
  MsColors get ms => Theme.of(this).extension<MsColors>() ?? MsColors.dark;
}

/// 全局当前配色：App 顶层在每次构建时同步（见 app.dart）。供无 context 的
/// helper 方法/静态构造直接取色（`msNow.textPrimary`）。有 context 时优先用 `context.ms`。
MsColors msNow = MsColors.dark;

ThemeData _base(Brightness b, MsColors ms) {
  final base = b == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    brightness: b,
    scaffoldBackgroundColor: ms.bg,
    extensions: [ms],
    colorScheme: (b == Brightness.dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(primary: ms.brand, secondary: ms.accentOn, error: ms.danger, surface: ms.card),
    textTheme: base.textTheme.apply(bodyColor: ms.textPrimary, displayColor: ms.textPrimary),
    cardTheme: CardThemeData(
      color: ms.card, elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: ms.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: ms.brand, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: ms.brand, foregroundColor: b == Brightness.dark ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

ThemeData buildDarkTheme()  => _base(Brightness.dark,  MsColors.dark);
ThemeData buildLightTheme() => _base(Brightness.light, MsColors.light);
// 兼容旧调用（app.dart 会改用 dark/light 双主题）。
ThemeData buildTheme() => buildDarkTheme();

/// 主题模式控制器：手动明/暗切换 + 持久化（不跟随系统）。
class ThemeController extends ChangeNotifier {
  static const _kKey = 'theme_mode';   // 'light' | 'dark'
  ThemeMode _mode = ThemeMode.light;   // 默认浅色
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_kKey);
      if (v == 'dark') _mode = ThemeMode.dark;
      else _mode = ThemeMode.light;   // 无记录/light → 浅色
    } catch (_) {}
    notifyListeners();
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    // 状态栏图标随主题反色。
    SystemChrome.setSystemUIOverlayStyle(
      _mode == ThemeMode.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    try {
      await (await SharedPreferences.getInstance())
          .setString(_kKey, _mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}
