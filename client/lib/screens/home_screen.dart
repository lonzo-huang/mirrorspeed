import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/portal_link.dart';
import '../providers/auth_provider.dart';
import '../providers/shared_node_provider.dart';
import '../models/free_node.dart';
import '../models/server_config.dart';
import '../utils/free_country.dart';
import '../providers/vpn_provider.dart';
import '../services/ad_service.dart';
import '../brand.dart';
import '../env.dart';
import '../theme.dart';
import '../app.dart' show rootMessengerKey;

// 广告仅在 Android/iOS 可用（AdMob 不支持 Windows/桌面）。
bool get _adsSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// 返回键 → 退到后台（不退出应用，VPN 保持运行）。
const MethodChannel _lifecycleChannel = MethodChannel('com.mirrorspeed.app/lifecycle');
Future<void> _moveAppToBackground() async {
  try { await _lifecycleChannel.invokeMethod('moveToBackground'); } catch (_) {}
}

bool _updateDialogShown = false;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ms   = context.ms;
    final auth = context.watch<AuthProvider>();
    final vpn  = context.watch<VpnProvider>();
    final shared = context.watch<SharedNodeProvider>();

    if (auth.forceUpdate || (auth.updateAvailable && !_updateDialogShown)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog(context, version: auth.latestVersion ?? '', force: auth.forceUpdate, url: auth.downloadUrl);
      });
    }

    final realServers = auth.displayServers.where((s) => !s.isDisplayOnly).toList();
    final server = vpn.activeServer ??
        (realServers.isNotEmpty
            ? realServers.first
            : (auth.displayServers.isNotEmpty ? auth.displayServers.first : null));

    final vpnBusy = vpn.isBusy && !vpn.isConnected;
    final showShared = shared.isConnected || shared.isConnecting ||
        (shared.preferShared && !vpn.isConnected && !vpnBusy);

    final connected     = showShared ? shared.isConnected : vpn.isConnected;
    final disconnecting = showShared ? shared.isDisconnecting : vpn.isDisconnecting;
    final connecting = (showShared ? (shared.isBusy || shared.autoTrying) : vpnBusy) && !disconnecting;

    Future<void> onConnect() async {
      if (showShared) {
        if (shared.isConnected || shared.isConnecting) {
          await shared.disconnect();
        } else if (shared.selected != null) {
          final ok = await shared.connectVerified(shared.selected!);
          if (!ok) {
            rootMessengerKey.currentState?.showSnackBar(SnackBar(
              content: Text(shared.error ?? tr('连接失败，请换一个节点', 'Connection failed, try another node')),
              backgroundColor: ms.danger, duration: const Duration(seconds: 4)));
          }
        } else {
          context.go('/servers');
        }
        return;
      }
      if (vpn.isConnected) {
        await vpn.disconnect();
      } else if (!auth.isLoggedIn) {
        context.go('/login');
      } else if (server == null || server.isDisplayOnly) {
        await auth.refreshConfigs();
      } else if (vpn.autoSelect) {
        await vpn.connectAuto(realServers);
      } else {
        await vpn.connect(server);
      }
    }

    // 状态副标题（不使用「连接已加密」）。
    final String statusText = showShared
        ? (connected ? '${tr('已连接', 'Connected')} · ${tr('免费节点', 'Free')}'
           : disconnecting ? tr('断 开 中', 'DISCONNECTING')
           : connecting ? tr('正 在 建 立 安 全 隧 道', 'ESTABLISHING SECURE TUNNEL')
           : tr('未 连 接', 'DISCONNECTED'))
        : (vpn.isConnected ? '${tr('已连接', 'Connected')} · ${vpn.statusLine}'
           : disconnecting ? tr('断 开 中', 'DISCONNECTING')
           : connecting ? tr('正 在 建 立 安 全 隧 道', 'ESTABLISHING SECURE TUNNEL')
           : tr('未 连 接', 'DISCONNECTED'));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _moveAppToBackground(); },
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [ms.bgGradTop, ms.bg],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              // 底部留足空间清开悬浮底部导航（extendBody），并保证内容可上滑。
              padding: const EdgeInsets.only(bottom: 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),

                  // 运营 banner（通告 / 更新 / 到期）
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(children: [
                      if (auth.announcement != null) _AnnouncementBanner(data: auth.announcement!),
                      if (auth.updateAvailable) _UpdateBanner(version: auth.latestVersion!),
                      if (auth.daysUntilExpiry != null && auth.daysUntilExpiry! <= 7)
                        _ExpiryBanner(days: auth.daysUntilExpiry!),
                    ]),
                  ),

                  const SizedBox(height: 12),

                  // 当前节点卡片
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _CurrentNodeCard(
                      label: showShared
                          ? '${tr('当前节点', 'Current')} · ${tr('免费节点', 'Free')} · ${tr('动态刷新', 'Dynamic')}'
                          : '${tr('当前节点', 'Current')} · ${tr('优质节点', 'Premium')} · ${vpn.routingMode == RoutingMode.smart ? tr('智能模式', 'Smart') : tr('全局模式', 'Global')}',
                      title: showShared
                          ? ((shared.active ?? shared.selected) != null
                              ? _sharedNodeTitle((shared.active ?? shared.selected)!)
                              : tr('未选择', 'Not selected'))
                          : (server != null ? '${server.flagEmoji} ${server.displayLabel(Brand.isZh)}' : tr('未选择', 'Not selected')),
                      latency: showShared ? null : (server?.displayLatencyMs != null ? '${server!.displayLatencyMs}ms' : null),
                      onTap: () => context.go('/servers'),
                    ),
                  ),

                  const SizedBox(height: 4),

                  _HeroConnect(
                    connected: connected, connecting: connecting, disconnecting: disconnecting,
                    onTap: (connecting || disconnecting) ? null : onConnect,
                  ),

                  const SizedBox(height: 8),

                  Center(child: Text(statusText,
                    style: TextStyle(
                      fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600,
                      color: connected ? ms.accentOn : ms.textSecondary))),

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _StatsRow(
                      connected: connected,
                      pingMs: showShared ? _sharedPing(shared)
                          : (vpn.isConnected ? (vpn.connectedPingMs ?? server?.displayLatencyMs) : server?.displayLatencyMs),
                      upStr:   vpn.isConnected ? vpn.uploadSpeedStr   : '0 KB/s',
                      downStr: vpn.isConnected ? vpn.downloadSpeedStr : '0 KB/s',
                    ),
                  ),

                  if (Brand.showSmartRouting) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Opacity(
                        opacity: (connected || connecting) ? 0.45 : 1.0,
                        child: _RoutingModeToggle(
                          mode: vpn.routingMode,
                          onChanged: (m) {
                            if (connected || connecting) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(tr('请先断开连接再切换模式', 'Disconnect first to switch mode')),
                                duration: const Duration(seconds: 2)));
                              return;
                            }
                            vpn.setRoutingMode(m);
                          },
                        ),
                      ),
                    ),
                  ],

                  // 免费时长卡片（正常 / 用完两种态）——非会员且非超流量挂起时显示。
                  if (vpn.isFreeTrial || (vpn.quotaExceeded && !vpn.isConnected)) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _FreeTimeCard(usedUp: vpn.quotaExceeded && !vpn.isConnected),
                    ),
                  ],

                  if (auth.isSuspended) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _QuotaSuspendedBanner(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showUpdateDialog(BuildContext context,
      {required String version, required bool force, required String url}) async {
    final ms = context.ms;
    if (!force) {
      if (_updateDialogShown) return;
      _updateDialogShown = true;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: AlertDialog(
          backgroundColor: ms.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.system_update_rounded, color: ms.brand, size: 20),
            const SizedBox(width: 8),
            Text(tr('发现新版本', 'Update available')),
          ]),
          content: Text(
            force
              ? tr('当前版本过旧，需更新到 v$version 才能继续使用。', 'Your version is outdated. Please update to v$version to continue.')
              : tr('新版本 v$version 已发布，建议立即更新以获得最新修复与体验。', 'Version v$version is available. Update now for the latest fixes and improvements.'),
            style: TextStyle(color: ms.textSecondary, fontSize: 13)),
          actions: [
            if (!force)
              TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text(tr('稍后', 'Later'), style: TextStyle(color: ms.textMuted))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ms.brand),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(tr('立即更新', 'Update now')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 头部：Logo + 名称 | 语言胶囊 + 明暗切换 ────────────────────────────────
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final theme = context.read<ThemeController>();
    final locale = context.read<LocaleController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset('assets/icon/app_icon.png', width: 40, height: 40, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Brand.appName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ms.textPrimary)),
          Text('MIRROR SPEED', style: TextStyle(fontSize: 9, letterSpacing: 2.5, color: ms.textMuted)),
        ])),
        // 语言胶囊
        _PillButton(
          onTap: () => locale.toggle(),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.translate_rounded, size: 15, color: ms.textSecondary),
            const SizedBox(width: 5),
            Text(Brand.isZh ? 'ZH' : 'EN',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ms.textSecondary)),
          ]),
        ),
        const SizedBox(width: 8),
        // 明暗切换
        _PillButton(
          circle: true,
          onTap: () => theme.toggle(),
          child: Icon(theme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            size: 17, color: ms.textSecondary),
        ),
      ]),
    );
  }
}

class _PillButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool circle;
  const _PillButton({required this.child, required this.onTap, this.circle = false});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: circle ? 40 : null, height: 40,
        alignment: Alignment.center,
        padding: circle ? null : const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: ms.pill,
          borderRadius: BorderRadius.circular(circle ? 20 : 20),
          border: Border.all(color: ms.cardBorder),
        ),
        child: child,
      ),
    );
  }
}

// ── 当前节点卡片 ────────────────────────────────────────────────────────────
class _CurrentNodeCard extends StatelessWidget {
  final String label;
  final String title;
  final String? latency;
  final VoidCallback onTap;
  const _CurrentNodeCard({required this.label, required this.title, this.latency, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: ms.card, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ms.cardBorder)),
        child: Row(children: [
          Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(color: ms.brand.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.public_rounded, color: ms.brand, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: ms.textSecondary)),
            const SizedBox(height: 3),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ms.textPrimary)),
          ])),
          if (latency != null) ...[
            Text(latency!, style: TextStyle(fontSize: 13, color: ms.accentOn, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded, color: ms.textMuted),
        ]),
      ),
    );
  }
}

// ── 中心连接按钮（同心旋转光环）────────────────────────────────────────────
class _HeroConnect extends StatefulWidget {
  final bool connected, connecting, disconnecting;
  final VoidCallback? onTap;
  const _HeroConnect({required this.connected, required this.connecting, this.disconnecting = false, this.onTap});
  @override State<_HeroConnect> createState() => _HeroConnectState();
}

class _HeroConnectState extends State<_HeroConnect> with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  @override void dispose() { _ring.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final active = widget.connected;
    final busy = widget.connecting || widget.disconnecting;
    // 强调色：已连接=绿；连接中=品牌薄荷；未连接=品牌薄荷（弱）。
    final c = active ? ms.accentOn : ms.brand;
    final spin = active || busy;
    Widget ringW(double size, double op, double mul) => AnimatedBuilder(
      animation: _ring,
      builder: (_, __) => Transform.rotate(
        angle: spin ? _ring.value * 2 * math.pi * mul : 0,
        child: Container(width: size, height: size, decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: (spin ? c : ms.textMuted).withOpacity(op), width: 1.3))),
      ),
    );
    // 中心圆：已连接=实心绿；否则=卡片色。
    final centerBg = active ? c : ms.card;
    final iconTextColor = active
        ? (context.read<ThemeController>().isDark ? const Color(0xFF0B1517) : Colors.white)
        : ms.textPrimary;
    return SizedBox(
      height: 210,
      child: Center(child: Stack(alignment: Alignment.center, children: [
        Container(width: 176, height: 176, decoration: BoxDecoration(shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withOpacity(active ? 0.28 : 0.12), blurRadius: 60, spreadRadius: 6)])),
        ringW(196, 0.30, 1.0),
        ringW(162, 0.45, -1.4),
        GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 138, height: 138,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: centerBg,
              border: Border.all(color: c.withOpacity(active ? 0.9 : 0.5), width: 3),
              boxShadow: [BoxShadow(color: c.withOpacity(active ? 0.5 : 0.22), blurRadius: active ? 50 : 30, spreadRadius: -6)],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              busy
                  ? SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3,
                      color: active ? iconTextColor : c))
                  : Icon(Icons.power_settings_new_rounded, size: 40, color: iconTextColor),
              const SizedBox(height: 6),
              Text(
                active ? tr('点击断开', 'Tap to stop')
                       : widget.disconnecting ? tr('断开中', 'Stopping')
                       : widget.connecting ? tr('连接中', 'Connecting') : tr('点击连接', 'Tap to connect'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: iconTextColor)),
            ]),
          ),
        ),
      ])),
    );
  }
}

// ── 三栏数据 ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final bool connected;
  final int? pingMs;
  final String upStr, downStr;
  const _StatsRow({required this.connected, this.pingMs, required this.upStr, required this.downStr});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    Widget item(String label, String value, String unit) => Expanded(child: Column(children: [
      Text(label, style: TextStyle(fontSize: 11, color: ms.textSecondary)),
      const SizedBox(height: 6),
      RichText(text: TextSpan(children: [
        TextSpan(text: value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
          color: connected ? ms.textPrimary : ms.textPrimary)),
        TextSpan(text: ' $unit', style: TextStyle(fontSize: 11, color: ms.textMuted)),
      ])),
    ]));
    final div = Container(width: 1, height: 30, color: ms.divider);
    // 解析 "288 KB/s" → value + unit。
    List<String> sp(String s) {
      final i = s.indexOf(' ');
      return i < 0 ? [s, ''] : [s.substring(0, i), s.substring(i + 1)];
    }
    final up = sp(upStr), down = sp(downStr);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: ms.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ms.cardBorder)),
      child: Row(children: [
        item(tr('延迟', 'Ping'), pingMs != null ? '$pingMs' : '--', 'ms'),
        div,
        item(tr('上传', 'Upload'), up[0], up[1]),
        div,
        item(tr('下载', 'Download'), down[0], down[1]),
      ]),
    );
  }
}

// ── 智能 / 全局 模式切换（两张并排卡片）───────────────────────────────────
class _RoutingModeToggle extends StatelessWidget {
  final RoutingMode mode;
  final ValueChanged<RoutingMode> onChanged;
  const _RoutingModeToggle({required this.mode, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _ToggleItem(
        label: tr('智能模式', 'Smart'), subtitle: tr('按黑/白名单规则代理', 'Rule-based proxy'),
        selected: mode == RoutingMode.smart, onTap: () => onChanged(RoutingMode.smart))),
      const SizedBox(width: 12),
      Expanded(child: _ToggleItem(
        label: tr('全局模式', 'Global'), subtitle: tr('所有流量代理', 'All traffic proxied'),
        selected: mode == RoutingMode.global, onTap: () => onChanged(RoutingMode.global))),
    ]);
  }
}

class _ToggleItem extends StatelessWidget {
  final String label, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleItem({required this.label, required this.subtitle, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? ms.brand.withOpacity(0.14) : ms.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? ms.brand : ms.cardBorder, width: selected ? 1.4 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
            color: selected ? ms.brand : ms.textPrimary)),
          const SizedBox(height: 1),
          Text(subtitle, style: TextStyle(fontSize: 11, color: ms.textSecondary)),
        ]),
      ),
    );
  }
}

// ── 免费时长卡片（正常态：进度条 + 看广告；用完态：红标题 + 两个按钮）───────
class _FreeTimeCard extends StatefulWidget {
  final bool usedUp;
  const _FreeTimeCard({required this.usedUp});
  @override State<_FreeTimeCard> createState() => _FreeTimeCardState();
}

class _FreeTimeCardState extends State<_FreeTimeCard> {
  bool _adBusy = false;
  bool _justRewarded = false;
  Timer? _rewardTimer;

  @override
  void initState() { super.initState(); AdService.instance.warmUp(); }
  @override void dispose() { _rewardTimer?.cancel(); super.dispose(); }

  String _fmt(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  Future<void> _watchAd() async {
    if (_adBusy) return;
    setState(() => _adBusy = true);
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!AdService.instance.rewardedReady) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('广告加载中，国内将自动通过共享节点加速加载，请稍候…', 'Loading ad, please wait…')),
        duration: const Duration(seconds: 20)));
    }
    await AdService.instance.showRewardedForReward(
      onEarned: () async {
        messenger.hideCurrentSnackBar();
        await vpn.addAdBonusMinutes(kAdRewardMinutes);
        if (!mounted) return;
        setState(() { _adBusy = false; _justRewarded = true; });
        _rewardTimer?.cancel();
        _rewardTimer = Timer(const Duration(seconds: 4), () { if (mounted) setState(() => _justRewarded = false); });
      },
      onUnavailable: () {
        if (!mounted) return;
        setState(() => _adBusy = false);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(tr('当前网络无法加载广告，可稍后重试或升级会员', 'Ads can\'t load now — try later or go Premium')),
          backgroundColor: context.ms.danger, duration: const Duration(seconds: 3)));
      },
    );
  }

  Future<void> _useFreeNode() async {
    final shared = context.read<SharedNodeProvider>();
    final ms = context.ms;
    await shared.connectBest();
    if (!mounted) return;
    if (shared.error != null && !shared.isConnected) {
      rootMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(shared.error!), backgroundColor: ms.danger, duration: const Duration(seconds: 4)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ms  = context.ms;
    final vpn = context.watch<VpnProvider>();
    final usedUp = widget.usedUp;
    final accent = usedUp ? ms.danger : ms.accentOn;
    final ratio = vpn.trialTotalSec > 0 ? (vpn.trialRemainingSec / vpn.trialTotalSec).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: ms.card, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ms.cardBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(usedUp ? Icons.timer_off_rounded : Icons.timer_outlined, size: 17, color: accent),
          const SizedBox(width: 8),
          Text(usedUp ? tr('免费时长已用完', 'Free time used up') : tr('今日免费时长', "Today's free time"),
            style: TextStyle(color: accent, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (!usedUp)
            Text(tr('剩余 ${_fmt(vpn.trialRemainingSec)}', '${_fmt(vpn.trialRemainingSec)} left'),
              style: TextStyle(color: ms.textSecondary, fontSize: 13, fontFamily: 'monospace')),
        ]),
        if (usedUp) ...[
          const SizedBox(height: 8),
          Text(
            tr('观看 1 分钟广告，即可继续使用 30 分钟优质服务器；也可以直接使用免费服务器。',
               'Watch a 1-min ad to get 30 min of Premium servers, or use a free server directly.'),
            style: TextStyle(color: ms.textSecondary, fontSize: 12.5, height: 1.45)),
        ] else ...[
          const SizedBox(height: 9),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: ratio, minHeight: 5,
              backgroundColor: ms.accentOn.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(ms.accentOn))),
        ],
        const SizedBox(height: 10),
        // 广告按钮（正常=虚线；用完=实心）；桌面无广告则用升级替代。
        if (_adsSupported)
          _justRewarded
            ? _dashedInfo(context, Icons.play_circle_fill_rounded,
                tr('+$kAdRewardMinutes 分钟优质时长已到账', '+$kAdRewardMinutes min Premium time added'))
            : (usedUp
                ? _solidBtn(context, _adBusy ? tr('广告播放中…', 'Ad playing…')
                    : tr('看广告增加$kAdRewardMinutes分钟优质节点时长', 'Watch ad · +$kAdRewardMinutes min'),
                    onTap: _adBusy ? null : _watchAd)
                : _dashedBtn(context, Icons.play_arrow_rounded,
                    tr('看广告增加$kAdRewardMinutes分钟优质节点时长', 'Watch ad · +$kAdRewardMinutes min Premium time'),
                    onTap: _adBusy ? null : _watchAd))
        else if (usedUp)
          _solidBtn(context, tr('升级会员 · 无限时长', 'Upgrade · Unlimited'), onTap: () => openPortal('/pricing')),
        // 直接使用免费服务器（仅用完态）
        if (usedUp) ...[
          const SizedBox(height: 10),
          _outlineBtn(context, Icons.wifi_rounded, tr('直接使用免费服务器', 'Use a free server'), onTap: _useFreeNode),
        ],
      ]),
    );
  }

  Widget _dashedBtn(BuildContext c, IconData icon, String label, {VoidCallback? onTap}) {
    final ms = c.ms;
    return GestureDetector(onTap: onTap, child: DottedBorderBox(color: ms.brand.withOpacity(0.5),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: ms.brand), const SizedBox(width: 8),
        Flexible(child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: ms.brand, fontSize: 13.5, fontWeight: FontWeight.w600))),
      ])));
  }

  Widget _dashedInfo(BuildContext c, IconData icon, String label) {
    final ms = c.ms;
    return DottedBorderBox(color: ms.accentOn.withOpacity(0.5),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: ms.accentOn), const SizedBox(width: 8),
        Flexible(child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: ms.accentOn, fontSize: 13.5, fontWeight: FontWeight.w700))),
      ]));
  }

  Widget _solidBtn(BuildContext c, String label, {VoidCallback? onTap}) {
    final ms = c.ms;
    final isDark = c.read<ThemeController>().isDark;
    return SizedBox(width: double.infinity, child: ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.play_arrow_rounded, size: 20, color: isDark ? Colors.black : Colors.white),
      label: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
        color: isDark ? Colors.black : Colors.white)),
      style: ElevatedButton.styleFrom(backgroundColor: ms.brand,
        padding: const EdgeInsets.symmetric(vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
    ));
  }

  Widget _outlineBtn(BuildContext c, IconData icon, String label, {VoidCallback? onTap}) {
    final ms = c.ms;
    return SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: ms.textPrimary),
      label: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ms.textPrimary)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: ms.cardBorder),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ));
  }
}

// 虚线边框盒子（看广告按钮用）。
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final Color color;
  const DottedBorderBox({super.key, required this.child, required this.color});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(color: color, radius: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color; final double radius;
  _DashedRectPainter({required this.color, required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1.3..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }
  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color;
}

// ── 运营 banners（主题感知，简化）─────────────────────────────────────────
class _UpdateBanner extends StatelessWidget {
  final String version;
  const _UpdateBanner({required this.version});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    return _BannerBox(color: ms.brand, icon: Icons.system_update_rounded,
      text: tr('发现新版本 v$version，点击前往下载更新', 'New version v$version — tap to update'),
      trailing: tr('更新 →', 'Update →'),
      onTap: () => launchUrl(Uri.parse('https://www.mirrorspeed.com/download'), mode: LaunchMode.externalApplication));
  }
}

class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnnouncementBanner({required this.data});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final title = (data['title'] ?? '') as String;
    final body  = (data['body']  ?? '') as String;
    final level = (data['level'] ?? 'info') as String;
    final color = level == 'warning' ? Colors.amber : level == 'critical' ? ms.danger : ms.brand;
    final url   = data['url'] as String?;
    return _BannerBox(color: color, icon: Icons.campaign_rounded,
      text: [title, body].where((s) => s.isNotEmpty).join('  '),
      onTap: (url != null && url.isNotEmpty)
          ? () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) : null);
  }
}

class _ExpiryBanner extends StatelessWidget {
  final int days;
  const _ExpiryBanner({required this.days});
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    final isUrgent = days <= 2;
    final color = isUrgent ? ms.danger : Colors.amber;
    final text = days == 0
        ? tr('您的订阅今天到期，请尽快续费', 'Your subscription expires today — please renew')
        : tr('您的订阅将在 $days 天后到期', 'Your subscription expires in $days days');
    return _BannerBox(color: color, icon: isUrgent ? Icons.warning_rounded : Icons.access_time_rounded,
      text: text, trailing: tr('续费 →', 'Renew →'), onTap: () => openPortal('/dashboard/billing'));
  }
}

class _BannerBox extends StatelessWidget {
  final Color color; final IconData icon; final String text; final String? trailing; final VoidCallback? onTap;
  const _BannerBox({required this.color, required this.icon, required this.text, this.trailing, this.onTap});
  @override
  Widget build(BuildContext context) {
    final w = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35))),
      child: Row(children: [
        Icon(icon, color: color, size: 16), const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500))),
        if (trailing != null) Text(trailing!, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );
    return onTap == null ? w : GestureDetector(onTap: onTap, child: w);
  }
}

class _QuotaSuspendedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ms = context.ms;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ms.gold.withOpacity(0.12), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ms.gold.withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline_rounded, color: ms.gold, size: 18), const SizedBox(width: 8),
          Expanded(child: Text(tr('今日流量已达上限', "Today's data limit reached"),
            style: TextStyle(color: ms.gold, fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 6),
        Text(tr('已超出当日免费流量阈值。请明日自动刷新，或升级会员享不限流量。',
               'You reached the daily free-data threshold. It resets tomorrow, or upgrade for unlimited data.'),
          style: TextStyle(color: ms.textSecondary, fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: OutlinedButton(
          onPressed: () => context.push('/vip'),
          style: OutlinedButton.styleFrom(foregroundColor: ms.gold, side: BorderSide(color: ms.gold.withOpacity(0.6)),
            padding: const EdgeInsets.symmetric(vertical: 11)),
          child: Text(tr('升级会员', 'Upgrade')))),
      ]),
    );
  }
}

// 共享节点当前测速延迟。
int? _sharedPing(SharedNodeProvider s) {
  final n = s.active ?? s.selected;
  if (n == null) return null;
  final l = s.latencyOf(n);
  return (l != null && l >= 0) ? l : null;
}

// 主页当前共享节点标题：「旗帜 本地化国家 · IP」。
String _sharedNodeTitle(FreeNode n) {
  final key = freeCountryKey(n.name);
  final flag = freeCountryFlag(key);
  final country = freeCountryLabel(key, Brand.isZh);
  final ip = freeLineName(n.name, n.server);
  final head = flag.isEmpty ? country : '$flag $country';
  return key.isEmpty ? ip : '$head · $ip';
}
