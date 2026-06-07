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
import 'brand.dart';
import 'services/ad_service.dart';

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
    // 免费额度从服务器拉取：auth 配置变化时同步给 VpnProvider。
    // 时间试用(#3)为强制额度；流量值仅作展示。
    _auth.addListener(() {
      _vpn.setDailyQuota(_auth.dailyQuotaBytes);
      _vpn.setTimeQuota(_auth.dailyQuotaSeconds);
      // 冷启动采纳已运行隧道后，把 activeServer 绑回上次节点。
      _vpn.bindActiveServer(_auth.displayServers);
    });

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
  ///
  /// 不再设登录墙（#7）：无论是否登录，打开 App 都直接进入连接界面 /home。
  /// 登录是可选的，由用户在「我的」页自行发起；登录成功后停留在当前页。
  String? _authRedirect(BuildContext context, GoRouterState state) {
    final loc = state.matchedLocation;
    // 初始化中：停在启动屏 / 回调页等待
    if (_auth.status == AuthStatus.loading) {
      return (loc == '/' || loc == '/login-callback') ? null : '/home';
    }
    // 启动屏 / OAuth 回调完成 → 进入主页
    if (loc == '/' || loc == '/login-callback') return '/home';
    // 登录成功后自动离开登录页回到主页（登录是可选入口，不是墙）
    if (loc == '/login' && _auth.status == AuthStatus.authenticated) return '/home';
    // 其余页面（/home /profile /login /no-subscription）一律放行，不强制跳转
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台/深度休眠恢复时，检查直连隧道是否在休眠期间因端口轮换+conntrack
    // 过期而失效；若已死则自动重连（见 VpnProvider.onAppResumed）。
    if (state == AppLifecycleState.resumed) {
      _vpn.onAppResumed();
      // 免费用户每次从后台切回都展示开屏广告（会员被 AdService 内部 _enabled 屏蔽）。
      AdService.instance.showAppOpenIfAvailable();
    }
    // 注意：detached（被系统回收/结束）时【不】断开 VPN——返回键/切后台/被杀都
    // 应保持隧道运行（前台服务），下次打开自动采纳。只有右上角「退出」键才主动断开。
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
        title:        Brand.appName,
        theme:        buildTheme(),
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
