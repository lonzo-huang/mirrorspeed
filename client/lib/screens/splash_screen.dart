import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>    _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().initialize().then((_) => _navigate());
    });
  }

  void _navigate() {
    final auth = context.read<AuthProvider>();
    switch (auth.status) {
      case AuthStatus.authenticated:
        context.go('/home');
      case AuthStatus.noSubscription:
        context.go('/no-subscription');
      default:
        context.go('/login');
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 96, height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kBrand, kBrandDark],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: kBrand.withOpacity(0.4), blurRadius: 32, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.shield_rounded, size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            const Text('MirrorSpeed VPN', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            Text('正在启动…', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ],
        ),
      ),
    );
  }
}
