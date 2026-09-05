import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';

/// 顶部快捷控件：明暗切换。各主页面 AppBar/头部复用，保持位置一致。
class MsTopControls extends StatelessWidget {
  const MsTopControls({super.key});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final theme = context.watch<ThemeController>();
    return GestureDetector(
      onTap: () => theme.toggle(),
      child: Container(
        width: 36, height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: ms.pill, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ms.cardBorder)),
        child: Icon(theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          size: 16, color: ms.textSecondary),
      ),
    );
  }
}
