import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/vpn_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/no_subscription_screen.dart';
import 'theme.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',               builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login',          builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/home',           builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/no-subscription', builder: (_, __) => const NoSubscriptionScreen()),

    // OAuth deep-link callback: mirrorspeed://login-callback
    GoRoute(path: '/login-callback', builder: (_, __) => const SplashScreen()),
  ],
);

class MirrorSpeedApp extends StatelessWidget {
  const MirrorSpeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => VpnProvider()..initialize()),
      ],
      child: MaterialApp.router(
        title:        'MirrorSpeed VPN',
        theme:        buildTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
