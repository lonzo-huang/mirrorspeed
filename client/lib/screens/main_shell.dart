import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../brand.dart';
import '../theme.dart';

/// 主界面 Shell —— 包裹 HomeScreen / ProfileScreen，提供底部导航栏。
/// 登录 / 无订阅 / 启动屏不使用此 Shell。
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = location.startsWith('/servers') ? 1
                        : location.startsWith('/vip')     ? 2
                        : location.startsWith('/profile') ? 3
                        : 0;

    return Scaffold(
      backgroundColor: kBg,
      body: child,
      extendBody: true,
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: kBg.withOpacity(0.82),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _NavItem(
                        icon:     Icons.bolt_rounded,
                        label:    tr('主页', 'Home'),
                        selected: selectedIndex == 0,
                        onTap:    () => context.go('/home'),
                      ),
                      _NavItem(
                        icon:     Icons.dns_rounded,
                        label:    tr('服务器', 'Servers'),
                        selected: selectedIndex == 1,
                        onTap:    () => context.go('/servers'),
                      ),
                      _NavItem(
                        icon:     Icons.workspace_premium_rounded,
                        label:    tr('会员', 'VIP'),
                        selected: selectedIndex == 2,
                        onTap:    () => context.go('/vip'),
                      ),
                      _NavItem(
                        icon:     Icons.person_rounded,
                        label:    tr('我的', 'Me'),
                        selected: selectedIndex == 3,
                        onTap:    () => context.go('/profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? kBrand : Colors.white.withOpacity(0.4);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label,
              style: TextStyle(color: color, fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
