import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../brand.dart';
import '../theme.dart';

/// 顶部快捷控件：语言胶囊(ZH/EN) + 明暗切换。各主页面 AppBar/头部复用，保持一致。
class MsTopControls extends StatelessWidget {
  const MsTopControls({super.key});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final theme = context.watch<ThemeController>();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _pill(
        ms,
        onTap: () => context.read<LocaleController>().toggle(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.translate_rounded, size: 14, color: ms.textSecondary),
          const SizedBox(width: 4),
          Text(Brand.isZh ? 'ZH' : 'EN',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ms.textSecondary)),
        ]),
      ),
      const SizedBox(width: 8),
      _pill(
        ms, circle: true,
        onTap: () => theme.toggle(),
        child: Icon(theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          size: 16, color: ms.textSecondary),
      ),
    ]);
  }

  Widget _pill(MsColors ms, {required Widget child, required VoidCallback onTap, bool circle = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: circle ? 36 : null, height: 36, alignment: Alignment.center,
          padding: circle ? null : const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: ms.pill, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ms.cardBorder)),
          child: child,
        ),
      );
}
