import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/vpn_provider.dart';
import 'providers/shared_node_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/main_shell.dart';
import 'screens/no_subscription_screen.dart';
import 'screens/vip_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/help_screen.dart';
import 'screens/server_list_screen.dart';
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
  late final SharedNodeProvider _shared;
  late final GoRouter     _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthProvider();
    _vpn  = VpnProvider()..initialize();
    _shared = SharedNodeProvider();
    // 两条隧道系统级互斥：连一条前先停另一条。
    _shared.onNeedStopOther = _vpn.disconnect;
    _vpn.onBeforeConnect    = () async {
      _shared.clearPreferShared();   // 用户改连优质节点 → 切回优质档
      await _shared.disconnect();
    };
    // 广告加载不到（国内直连被墙）时，经随机共享节点把广告请求代理出去。
    AdService.instance.onNeedProxyForAds = () async {
      if (_vpn.isConnected) return;   // 已有优质隧道就不折腾
      await _shared.connectRandomForAd();
    };
    // #5 冷启动清理：停掉上次未正常退出而残留的 sing-box 隧道，避免死 tun 黑洞
    // 导致拉不到配置、一直卡在加载。冷启动 = 本 initState 只执行一次。
    _shared.disconnect();
    // #4 启动即后台预热共享节点（拉清单 + 测速），用户点进去就已就绪，不显慢。
    Future(() async {
      await _shared.load();
      await _shared.testAll();
    });
    // 免费额度从服务器拉取：auth 配置变化时同步给 VpnProvider。
    // 时间试用(#3)为强制额度；流量值仅作展示。
    var _premiumWarmed = false;
    _auth.addListener(() {
      _vpn.setDailyQuota(_auth.dailyQuotaBytes);
      _vpn.setTimeQuota(_auth.dailyQuotaSeconds);
      // 冷启动采纳已运行隧道后，把 activeServer 绑回上次节点。
      _vpn.bindActiveServer(_auth.displayServers);
      // #4 配置就绪后后台预测一次优质节点延迟（只做一次），进列表即有数据。
      final servers = _auth.displayServers;
      if (!_premiumWarmed && servers.isNotEmpty) {
        _premiumWarmed = true;
        _vpn.measureLatencies(servers, rounds: 1);
      }
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

        // ── 二级页（全屏，自带返回；从“我的”内打开）────────────
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/help',     builder: (_, __) => const HelpScreen()),

        // ── 主界面（带底部导航栏：主页 / 服务器 / 会员 / 我的）──
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(path: '/home',    builder: (_, __) => const HomeScreen()),
            GoRoute(path: '/servers', builder: (_, __) => const ServerListScreen()),
            GoRoute(path: '/vip',     builder: (_, __) => const VipScreen()),
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
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.hidden) {
      // 切后台/即将被冻结或强杀前的最后机会：强制把试用状态落盘（flush），
      // 避免任务管理器强杀后免费额度/看广告奖励丢失被重置到 30 分钟。
      _vpn.saveTrialState();
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
        ChangeNotifierProvider.value(value: _shared),
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
