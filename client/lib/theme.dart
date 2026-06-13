import 'package:flutter/material.dart';

// ── 品牌色 ───────────────────────────────────────────────────
const kBrand     = Color(0xFF6366F1);  // Indigo-500
const kBrandDark = Color(0xFF4F46E5);  // Indigo-600
const kSuccess   = Color(0xFF22C55E);  // Green-500
const kDanger    = Color(0xFFEF4444);  // Red-500
const kSurface   = Color(0xFF1E1E2E);  // Dark surface
const kCard      = Color(0xFF2A2A3C);  // Card background
const kBg        = Color(0xFF141421);  // Page background

// ── 新 UI 设计令牌（设计师方案；旧常量保留给「我的」页）──────────
const kPanel     = Color(0xFF24273A);  // 抬升面板/卡片（panel）
const kAccentOn  = Color(0xFF34E0A1);  // 连接态薄荷绿（connected accent）
const kGold      = Color(0xFFE8C766);  // VIP 金色
const kMuted     = Color(0xFF8A8CA3);  // 次要文字

ThemeData buildTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      primary:   kBrand,
      secondary: kBrandDark,
      surface:   kSurface,
      error:     kDanger,
    ),
    // Use system default font (Roboto/SF) — Google Fonts CDN is blocked in China
    // and can corrupt Flutter's font registry, causing MaterialIcons to render as squares.
    textTheme: base.textTheme.apply(
      bodyColor:    Colors.white,
      displayColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      color:       kCard,
      elevation:   0,
      shape:       RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:      true,
      fillColor:   kCard,
      border:      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:   BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:   const BorderSide(color: kBrand, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kBrand,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
