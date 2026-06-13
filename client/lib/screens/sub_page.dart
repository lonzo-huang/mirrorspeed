import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';

/// 二级页通用骨架：顶部 sticky 头部（返回 + 标题），深色背景。
class SubPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const SubPage({super.key, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(children: [
                IconButton(
                  onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: Colors.white70,
                ),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
                ])),
              ]),
            ),
            Expanded(child: SingleChildScrollView(child: child)),
          ],
        ),
      ),
    );
  }
}
