import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../brand.dart';
import '../theme.dart';

const _kCyan = Color(0xFF38E0D0);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ring;   // 持续旋转的光环
  late final AnimationController _enter;  // logo 入场
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ring  = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _scale = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack);

    // 触发鉴权初始化；完成后 AuthProvider 通知 → GoRouter 自动跳转。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initialize();
    });
  }

  @override
  void dispose() { _ring.dispose(); _enter.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06121A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3), radius: 1.0,
            colors: [Color(0x2634E0A1), Color(0x0038E0D0), Color(0xFF06121A)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240, height: 240,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 外环（正转）
                    AnimatedBuilder(
                      animation: _ring,
                      builder: (_, __) => Transform.rotate(
                        angle: _ring.value * 2 * math.pi,
                        child: Container(
                          width: 240, height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _kCyan.withOpacity(0.18), width: 1),
                          ),
                        ),
                      ),
                    ),
                    // 内环（反转，虚线感用渐变描边模拟）
                    AnimatedBuilder(
                      animation: _ring,
                      builder: (_, __) => Transform.rotate(
                        angle: -_ring.value * 2 * math.pi * 1.4,
                        child: Container(
                          width: 184, height: 184,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: kAccentOn.withOpacity(0.30), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    // 辉光
                    Container(
                      width: 150, height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _kCyan.withOpacity(0.25), blurRadius: 60, spreadRadius: 10)],
                      ),
                    ),
                    // Logo
                    ScaleTransition(
                      scale: _scale,
                      child: Container(
                        width: 112, height: 112,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kAccentOn, _kCyan],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [BoxShadow(
                            color: kAccentOn.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 12))],
                        ),
                        child: const Icon(Icons.shield_rounded, size: 56, color: Color(0xFF06121A)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              Text(Brand.appName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text(tr('高速安全，全球加速', 'Fast · Secure · Worldwide').toUpperCase(),
                style: TextStyle(color: kAccentOn.withOpacity(0.8), fontSize: 10, letterSpacing: 4)),
              const SizedBox(height: 36),
              // 进度条
              SizedBox(
                width: 176,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.06),
                    valueColor: const AlwaysStoppedAnimation(_kCyan),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
