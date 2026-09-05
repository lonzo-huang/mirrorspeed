import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';

/// 二级页通用骨架：顶部 sticky 头部（返回 + 标题），深色背景。
class SubPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;   // 头部右侧（如语言/主题切换）
  const SubPage({super.key, required this.title, this.subtitle, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: msNow.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: msNow.textSecondary.withOpacity(0.06))),
              ),
              child: Row(children: [
                IconButton(
                  onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: msNow.textSecondary,
                ),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: msNow.textSecondary.withOpacity(0.4))),
                ])),
                if (trailing != null) trailing!,
                const SizedBox(width: 4),
              ]),
            ),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}
