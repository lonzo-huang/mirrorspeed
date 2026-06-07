import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/vpn_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/main_shell.dart';
import 'screens/no_subscription_screen.dart';
import 'theme.dart';
import 'env.dart';

class MirrorSpeedApp extends StatefulWidget {
  const MirrorSpeedApp({super.key});
  @override State<MirrorSpeedApp> createState() => _MirrorSpeedAppState();
}

class _MirrorSpeedAppState extends State<MirrorSpeedApp>
    with WidgetsBindingObserver {
  late final AuthProvider _auth;
  late final VpnProvider  _vpn;
  late final GoRouter     _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthProvider();
    _vpn  = VpnProvider()..initialize();

    _router = GoRouter(
      initialLocation: '/',
      // GoRouter re-evaluates redirect whenever AuthProvider calls notifyListeners()
      refreshListenable: _auth,
      redirect: _authRedirect,
      routes: [
        GoRoute(path: '/',                builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
        GoRoute(path: '/no-subscription', builder: (_, __) => const NoSubscriptionScreen()),
        // OAuth / magic-link callback deep link (mirrorspeed://login-callback)
        GoRoute(path: '/login-callback',  builder: (_, __) => const SplashScreen()),

        // ── 主界面（带底部导航栏）────────────────────────────
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(path: '/home',    builder: (_, __) => const HomeScreen()),
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ],
        ),
      ],
    );
  }

  /// Central auth redirect — called by GoRouter on every notifyListeners().
  String? _authRedirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    switch (_auth.status) {
      case AuthStatus.loading:
        // Stay on splash / login-callback while auth initialises or PKCE completes
        return null;
      case AuthStatus.authenticated:
        if (loc == '/' || loc == '/login' || loc == '/login-callback') {
          return '/home';
        }
        return null;
      case AuthStatus.noSubscription:
        return loc == '/no-subscription' ? null : '/no-subscription';
      case AuthStatus.unauthenticated:
        return loc == '/login' ? null : '/login';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台/深度休眠恢复时，检查直连隧道是否在休眠期间因端口轮换+conntrack
    // 过期而失效；若已死则自动重连（见 VpnProvider.onAppResumed）。
    if (state == AppLifecycleState.resumed) {
      _vpn.onAppResumed();
    } else if (state == AppLifecycleState.detached) {
      // 应用即将退出：拆除隧道并清理路由，避免退出后路由表残留导致断网。
      // 注意只在 detached（终止）时拆除，paused（切后台）保持连接不动。
      _vpn.disconnect();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _vpn),
      ],
      child: MaterialApp.router(
        title:        kIsCnFlavor ? '镜速加速器' : 'MirrorSpeed VPN',
        theme:        buildTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
