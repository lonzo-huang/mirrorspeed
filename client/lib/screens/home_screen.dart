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
import '../utils/free_country.dart';
import '../providers/vpn_provider.dart';
import '../services/ad_service.dart';
import '../models/server_config.dart';
import '../brand.dart';
import '../env.dart';
import '../theme.dart';

// 广告仅在 Android/iOS 可用（AdMob 不支持 Windows/桌面）。
bool get _adsSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// 返回键 → 退到后台（不退出应用，VPN 保持运行）；退出由右上角退出键负责。
const MethodChannel _lifecycleChannel = MethodChannel('com.mirrorspeed.app/lifecycle');
Future<void> _moveAppToBackground() async {
  try { await _lifecycleChannel.invokeMethod('moveToBackground'); } catch (_) {}
}

// 启动更新提示：每次 App 运行最多弹一次（强制更新除外，强制会持续拦截）。
bool _updateDialogShown = false;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vpn  = context.watch<VpnProvider>();
    final shared = context.watch<SharedNodeProvider>();

    // 在线版本提示：强制更新(min_version)→不可关闭的拦截弹窗；普通新版本→可稍后的提示。
    if (auth.forceUpdate || (auth.updateAvailable && !_updateDialogShown)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog(context, version: auth.latestVersion ?? '', force: auth.forceUpdate, url: auth.downloadUrl);
      });
    }

    // 优先用真实节点（已登录配置已加载）；否则退回展示节点（公开列表）。
    final realServers = auth.displayServers.where((s) => !s.isDisplayOnly).toList();
    final server = vpn.activeServer ??
        (realServers.isNotEmpty
            ? realServers.first
            : (auth.displayServers.isNotEmpty ? auth.displayServers.first : null));

    // #7 首屏统一入口：当前处于哪个档位（共享=sing-box / 优质=WireGuard）。
    // 共享已连/连接中，或用户偏好共享且优质未连 → 首屏由共享档接管。
    final vpnBusy = vpn.isBusy && !vpn.isConnected;
    final showShared = shared.isConnected || shared.isConnecting ||
        (shared.preferShared && !vpn.isConnected && !vpnBusy);

    final connected  = showShared ? shared.isConnected : vpn.isConnected;
    final connecting = showShared ? (shared.isBusy || shared.autoTrying) : vpnBusy;

    Future<void> onConnect() async {
      if (showShared) {
        // 共享档：连/断 sing-box（连的是最近选择的共享节点）。
        if (shared.isConnected || shared.isConnecting) {
          await shared.disconnect();
        } else if (shared.selected != null) {
          await shared.connectSmart(shared.selected!);
        } else {
          context.go('/servers');   // 还没选过共享节点 → 去列表选
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

    return PopScope(
      // 返回键不退出应用：拦截后退到后台（合规且保持连接）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _moveAppToBackground();
      },
      child: Scaffold(
        backgroundColor: kBg,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 头部 ──────────────────────────────────────
                const _Header(),

                // ── 通告 / 更新 / 到期 banner ──────────────────
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

                // ── 当前节点卡片（顶部，截图样式）───────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _CurrentNodeCard(
                    label: showShared
                        ? '${tr('当前节点', 'Current')}：${tr('免费节点·动态刷新', 'Free·Dynamic')}'
                        : '${tr('当前节点', 'Current')}：${tr('优质节点', 'Premium')} - ${vpn.routingMode == RoutingMode.smart ? tr('智能模式', 'Smart') : tr('全局模式', 'Global')}',
                    title: showShared
                        ? ((shared.active ?? shared.selected) != null
                            ? _sharedNodeTitle((shared.active ?? shared.selected)!)
                            : tr('未选择', 'Not selected'))
                        : (server != null ? '${server.flagEmoji} ${server.displayLabel(Brand.isZh)}' : tr('未选择', 'Not selected')),
                    latency: showShared ? null : (server?.displayLatencyMs != null ? '${server!.displayLatencyMs}ms' : null),
                    onTap: () => context.go('/servers'),   // 统一进服务器页（按偏好自动落到共享/优质 tab）
                  ),
                ),

                const SizedBox(height: 8),

                // ── 中心连接按钮（光环）────────────────────────
                _HeroConnect(
                  connected:  connected,
                  connecting: connecting,
                  onTap:      connecting ? null : onConnect,
                ),

                const SizedBox(height: 10),

                // ── 状态副标题 ─────────────────────────────────
                Center(
                  child: Text(
                    showShared
                        ? (connected
                            ? '${tr('已连接', 'Connected')} · ${tr('共享节点', 'Shared')}'
                            : (connecting ? tr('连接中', 'Connecting') : tr('未连接', 'Disconnected')).toUpperCase())
                        : (vpn.isConnected
                            ? '${vpn.statusLine}${server != null ? ' · ${server.displayLabel(Brand.isZh)}' : ''}'
                            : (connecting ? vpn.statusLine : tr('未连接', 'Disconnected')).toUpperCase()),
                    style: TextStyle(
                      fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.w600,
                      color: connected ? kAccentOn : Colors.white.withOpacity(0.35),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── 三栏数据：延迟 / 上传 / 下载 ───────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _StatsRow(
                    connected: connected,
                    // 已连接：显示每 30s 刷新的优化延迟（首测前回退到节点延迟）；
                    // 未连接：显示所选节点的校正延迟。共享档显示共享节点测速延迟。
                    pingMs:    showShared
                        ? _sharedPing(shared)
                        : (vpn.isConnected
                            ? (vpn.connectedPingMs ?? server?.displayLatencyMs)
                            : server?.displayLatencyMs),
                    upStr:     vpn.isConnected ? vpn.uploadSpeedStr   : '0 B/s',
                    downStr:   vpn.isConnected ? vpn.downloadSpeedStr : '0 B/s',
                  ),
                ),

                // ── 智能 / 全局 切换（仅中文版）────────────────
                if (Brand.showSmartRouting) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    // #6 路由模式仅在连接时应用到隧道，连接中切换不生效 → 连接后禁用切换。
                    child: Opacity(
                      opacity: (connected || connecting) ? 0.45 : 1.0,
                      child: _RoutingModeToggle(
                        mode:      vpn.routingMode,
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

                // ── 超额升级 / 免费试用 + 看广告 ───────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [
                    if (vpn.quotaExceeded && !vpn.isConnected) ...[
                      const SizedBox(height: 14),
                      _UpgradeButton(),
                      // 广告仅 Android/iOS；Windows/桌面额度用尽只引导升级(方案 A)。
                      if (_adsSupported) ...[
                        const SizedBox(height: 10),
                        const _AdExtendButton(),
                      ],
                    ] else if (vpn.isFreeTrial) ...[
                      const SizedBox(height: 14),
                      // #3 免费时长进度条 + 看广告合并为一张卡片
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: kPanel,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(children: [
                          _TrialBar(
                            remainingSec: vpn.trialRemainingSec,
                            totalSec:     vpn.trialTotalSec,
                            exceeded:     vpn.quotaExceeded,
                            boxed:        false,
                          ),
                          if (_adsSupported) ...[
                            Divider(height: 18, color: Colors.white.withOpacity(0.08)),
                            const _AdExtendButton(compact: true),
                          ],
                        ]),
                      ),
                    ],
                  ]),
                ),

                // ── 今日流量已达上限（免费用户超额被挂起）────────
                if (auth.isSuspended) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _QuotaSuspendedBanner(),
                  ),
                ],

                // ── 错误提示 ───────────────────────────────────
                // 主页不再直接显示任何错误横幅（体验优化）：错误统一进「我的 → 错误信息」查看。
                const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 在线版本更新弹窗。force=true 时不可关闭(强制更新),否则可"稍后"。
  Future<void> _showUpdateDialog(BuildContext context,
      {required String version, required bool force, required String url}) async {
    if (!force) {
      if (_updateDialogShown) return;
      _updateDialogShown = true;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,   // 强制更新时拦截返回键
        child: AlertDialog(
          backgroundColor: kCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.system_update_rounded, color: kBrand, size: 20),
            const SizedBox(width: 8),
            Text(tr('发现新版本', 'Update available')),
          ]),
          content: Text(
            force
              ? tr('当前版本过旧，需更新到 v$version 才能继续使用。',
                   'Your version is outdated. Please update to v$version to continue.')
              : tr('新版本 v$version 已发布，建议立即更新以获得最新修复与体验。',
                   'Version v$version is available. Update now for the latest fixes and improvements.'),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            if (!force)
              TextButton(onPressed: () => Navigator.pop(ctx),
                child: Text(tr('稍后', 'Later'), style: const TextStyle(color: Colors.white54))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kBrand),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(tr('立即更新', 'Update now')),
            ),
          ],
        ),
      ),
    );
  }

}

// 延迟颜色点（基于校正后的延迟，与服务器列表信号格一致）：
//   ≤100 绿 · ≤200 浅绿 · ≤300 黄 · >300 红 · 测量中灰
Color latencyColor(int? ms) {
  if (ms == null)   return Colors.white38;
  if (ms <= 100)    return kSuccess;
  if (ms <= 200)    return Colors.lightGreen;
  if (ms <= 300)    return Colors.amber;
  return kDanger;
}

class LatencyDot extends StatelessWidget {
  final int? ms;
  const LatencyDot({super.key, required this.ms});
  @override
  Widget build(BuildContext context) {
    final c = latencyColor(ms);
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(
        color: c, shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withOpacity(0.5), blurRadius: 6)],
      ),
    );
  }
}

// ── 头部：Logo + 名称（退出已移至「我的」）─────────────────────────
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.asset('assets/icon/app_icon.png', width: 36, height: 36, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(Brand.appName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('MIRROR SPEED', style: TextStyle(fontSize: 9, letterSpacing: 2, color: Colors.white.withOpacity(0.35))),
        ])),
        // 会员中心（金色胶囊）
        GestureDetector(
          onTap: () => context.go('/vip'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8B44A).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8B44A).withOpacity(0.45)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.workspace_premium_rounded, color: Color(0xFFE8B44A), size: 15),
              const SizedBox(width: 5),
              Text(tr('会员中心', 'Premium'),
                style: const TextStyle(color: Color(0xFFE8B44A), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── 中心连接按钮（同心旋转光环 + 辉光）──────────────────────────────
class _HeroConnect extends StatefulWidget {
  final bool connected;
  final bool connecting;
  final VoidCallback? onTap;
  const _HeroConnect({required this.connected, required this.connecting, this.onTap});
  @override State<_HeroConnect> createState() => _HeroConnectState();
}

class _HeroConnectState extends State<_HeroConnect> with SingleTickerProviderStateMixin {
  late final AnimationController _ring =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  @override void dispose() { _ring.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final active = widget.connected;
    final c = active ? kAccentOn : kBrand;
    final spin = widget.connected || widget.connecting;
    Widget ringW(double size, double op, double mul) => AnimatedBuilder(
      animation: _ring,
      builder: (_, __) => Transform.rotate(
        angle: spin ? _ring.value * 2 * math.pi * mul : 0,
        child: Container(width: size, height: size, decoration: BoxDecoration(
          shape: BoxShape.circle, border: Border.all(color: c.withOpacity(op), width: 1.2))),
      ),
    );
    return SizedBox(
      height: 200,
      child: Center(child: Stack(alignment: Alignment.center, children: [
        Container(width: 170, height: 170, decoration: BoxDecoration(shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withOpacity(0.16), blurRadius: 60, spreadRadius: 6)])),
        ringW(180, 0.20, 1.0),
        ringW(150, 0.30, -1.4),
        GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 128, height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: const Color(0xFF181A28),
              border: Border.all(color: c.withOpacity(0.5), width: 4),
              boxShadow: [BoxShadow(color: c.withOpacity(active ? 0.45 : 0.30), blurRadius: active ? 50 : 34, spreadRadius: -8)],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              widget.connecting
                  ? SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: c))
                  : Icon(Icons.power_settings_new_rounded, size: 38, color: active ? kAccentOn : Colors.white),
              const SizedBox(height: 6),
              Text(
                active ? tr('已连接', 'Connected')
                       : widget.connecting ? tr('连接中', 'Connecting') : tr('点击连接', 'Tap to connect'),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? kAccentOn : Colors.white)),
            ]),
          ),
        ),
      ])),
    );
  }
}

// ── 三栏数据 ─────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final bool connected;
  final int? pingMs;
  final String upStr;
  final String downStr;
  const _StatsRow({required this.connected, this.pingMs, required this.upStr, required this.downStr});
  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, {bool accent = false}) => Expanded(child: Column(children: [
      Text(label.toUpperCase(), style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: Colors.white.withOpacity(0.4))),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600,
        color: accent ? kAccentOn : Colors.white)),
    ]));
    final div = Container(width: 1, height: 26, color: Colors.white.withOpacity(0.07));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(color: kPanel.withOpacity(0.6), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Row(children: [
        item(tr('延迟', 'Ping'), pingMs != null ? '${pingMs}ms' : '-- ms', accent: connected),
        div,
        item(tr('上传', 'Upload'), upStr, accent: connected),
        div,
        item(tr('下载', 'Download'), downStr, accent: connected),
      ]),
    );
  }
}

// ── 当前节点卡片 ─────────────────────────────────────────────────
class _NodeCard extends StatelessWidget {
  final ServerConfig server;
  final bool auto;
  final VoidCallback onTap;
  const _NodeCard({required this.server, required this.auto, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ms = server.displayLatencyMs;
    final c  = auto ? kAccentOn : Colors.amber;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Row(children: [
          Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
            child: Text(server.flagEmoji, style: const TextStyle(fontSize: 22))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(server.displayLabel(Brand.isZh), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              const SizedBox(width: 6),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.withOpacity(0.3))),
                child: Text(auto ? tr('智能', 'Auto') : tr('手动', 'Manual'),
                  style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: kBrand, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('${ms != null ? '$ms' : '--'}ms · ${tr('负载', 'load')} ${server.loadPercent}%',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white.withOpacity(0.45))),
            ]),
          ])),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.35)),
        ]),
      ),
    );
  }
}


// 共享节点当前测速延迟（无有效样本返回 null）。
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

// ── 顶部「当前节点」卡片（截图样式：图标 | 小标签+节点名 | 延迟 | ›）────────
class _CurrentNodeCard extends StatelessWidget {
  final String label;       // 「当前节点：优质节点 - 智能模式」
  final String title;       // 「🇪🇸 西班牙 01」
  final String? latency;    // 「90ms」/ null
  final VoidCallback onTap;
  const _CurrentNodeCard({required this.label, required this.title, this.latency, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(11)),
            child: Icon(Icons.public_rounded, color: Colors.white.withOpacity(0.7), size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45))),
            const SizedBox(height: 3),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ])),
          if (latency != null) ...[
            Text(latency!, style: const TextStyle(fontSize: 13, color: kAccentOn, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
          ],
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.35)),
        ]),
      ),
    );
  }
}

// ── 当前共享节点卡片 ─────────────────────────────────────────────────
class _SharedNodeCard extends StatelessWidget {
  final FreeNode? node;
  final VoidCallback onTap;
  const _SharedNodeCard({required this.node, required this.onTap});

  // 从脏节点名里抽旗帜+国家码；抽不到用清理后的短名。
  String _title(FreeNode n) {
    final runes = n.name.runes.toList();
    const base = 0x1F1E6;
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i] - base, b = runes[i + 1] - base;
      if (a >= 0 && a <= 25 && b >= 0 && b <= 25) {
        final flag = String.fromCharCodes([runes[i], runes[i + 1]]);
        return '$flag ${String.fromCharCode(65 + a)}${String.fromCharCode(65 + b)}';
      }
    }
    var s = n.name.replaceAll(RegExp(r'\d+(\.\d+)?\s*[KMG]B/s'), '').split('|').first.trim();
    if (s.length > 20) s = '${s.substring(0, 20)}…';
    return s.isEmpty ? n.server : s;
  }

  @override
  Widget build(BuildContext context) {
    final n = node;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPanel, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Row(children: [
          Container(width: 42, height: 42, alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.public_rounded, color: kBrand, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n == null ? tr('未选择', 'Not selected') : _title(n),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(n == null ? tr('点击选择共享节点', 'Tap to choose') : '${n.protocol.toUpperCase()} · ${n.server}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45))),
          ])),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.35)),
        ]),
      ),
    );
  }
}

// ── 免费试用倒计时条（按时间）────────────────────────────────────────────────
class _TrialBar extends StatelessWidget {
  final int  remainingSec;
  final int  totalSec;
  final bool exceeded;
  final bool boxed;   // false=去掉自身边框/底色，用于嵌入合并卡片
  const _TrialBar({ required this.remainingSec, required this.totalSec, required this.exceeded, this.boxed = true });

  String _fmt(int s) {
    final m = s ~/ 60, sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = totalSec > 0 ? (remainingSec / totalSec).clamp(0.0, 1.0) : 0.0;
    final color = exceeded ? kDanger : (ratio < 0.2 ? Colors.amber : kSuccess);
    return Container(
      padding: boxed
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
          : EdgeInsets.zero,
      decoration: boxed
          ? BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2)),
            )
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timer_outlined, size: 13, color: color),
          const SizedBox(width: 6),
          Text(tr('今日免费时长', "Today's free time"), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(
            exceeded ? tr('已用完', 'Used up') : tr('剩余 ${_fmt(remainingSec)}', '${_fmt(remainingSec)} left'),
            style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ]),
    );
  }
}

// ── 看广告延长时长按钮（激励视频，仅 Android/iOS）──────────────────────────────
class _AdExtendButton extends StatefulWidget {
  final bool compact;
  final String? label;   // 自定义文案（如「今日免费时长已用完，看广告 +30 分钟」）
  const _AdExtendButton({ this.compact = false, this.label });
  @override State<_AdExtendButton> createState() => _AdExtendButtonState();
}

class _AdExtendButtonState extends State<_AdExtendButton> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 预热激励广告，确保用户点击时已缓存好、能立刻播放（#4）。
    AdService.instance.warmUp();
  }

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    final vpn = context.read<VpnProvider>();
    final messenger = ScaffoldMessenger.of(context);
    // #3 广告未就绪（可能国内直连加载不了）→ 提示正在经共享节点加载，请稍候。
    if (!AdService.instance.rewardedReady) {
      messenger.showSnackBar(SnackBar(
        content: Text(tr('广告加载中，国内将自动通过共享节点加速加载，请稍候…',
            'Loading ad — using a shared node in China, please wait…')),
        duration: const Duration(seconds: 20),
      ));
    }
    // 看**一条** Rewarded 激励广告，看完(到达奖励点)立即发放 +30 分钟。
    await AdService.instance.showRewardedForReward(
      onEarned: () async {
        messenger.hideCurrentSnackBar();
        await vpn.addAdBonusMinutes(kAdRewardMinutes);
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(
          content: Text(tr('已解锁 +$kAdRewardMinutes 分钟免费时长 🎉', 'Unlocked +$kAdRewardMinutes min of free time 🎉')),
          backgroundColor: kSuccess, duration: const Duration(seconds: 2)));
      },
      onUnavailable: () {
        if (!mounted) return;
        setState(() => _busy = false);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(tr('当前网络无法加载广告，可稍后重试或升级会员', 'Ads can\'t load on the current network — try again later or go Premium')),
          backgroundColor: kDanger, duration: const Duration(seconds: 3)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label ?? tr('看广告增加$kAdRewardMinutes分钟优质节点时长', 'Watch ad · +$kAdRewardMinutes min Premium time');
    if (widget.compact) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: _busy ? null : _watch,
          icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: kBrand),
        ),
      );
    }
    return _PromoCard(
      icon: Icons.card_giftcard_rounded, iconColor: kBrand,
      title: label,
      subtitle: tr('每日可用', 'Available daily'),
      onTap: _busy ? null : _watch,
    );
  }
}

// ── 统一促销卡（图标圈 | 标题+副标题 | ›）──────────────────────────────
class _PromoCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final VoidCallback? onTap;
  final bool purple;   // 升级会员用紫色渐变
  const _PromoCard({
    required this.icon, required this.iconColor, required this.title,
    required this.subtitle, this.onTap, this.purple = false,
  });
  @override
  Widget build(BuildContext context) {
    final titleColor = purple ? Colors.white : Colors.white.withOpacity(0.92);
    final subColor   = purple ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.45);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          gradient: purple
              ? const LinearGradient(colors: [Color(0xFF7C5CF0), Color(0xFF5B45C8)])
              : null,
          color: purple ? null : kPanel,
          borderRadius: BorderRadius.circular(16),
          border: purple ? null : Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          Container(width: 40, height: 40, alignment: Alignment.center,
            decoration: BoxDecoration(
              color: purple ? Colors.white.withOpacity(0.18) : iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: purple ? Colors.white : iconColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: titleColor)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: subColor)),
          ])),
          Icon(Icons.chevron_right_rounded, color: (purple ? Colors.white : Colors.white).withOpacity(purple ? 0.85 : 0.35)),
        ]),
      ),
    );
  }
}

// ── 超额升级：免费时长已用完卡 + 升级会员卡（截图样式）──────────────────
class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton();

  @override
  Widget build(BuildContext context) => Column(children: [
    _PromoCard(
      icon: Icons.shield_outlined, iconColor: kAccentOn,
      title: tr('免费时长已用完', 'Free time used up'),
      subtitle: tr('明日自动恢复', 'Resets tomorrow'),
    ),
    _PromoCard(
      icon: Icons.workspace_premium_rounded, iconColor: Colors.white, purple: true,
      title: tr('升级会员 · 无限时长', 'Upgrade · Unlimited'),
      subtitle: tr('畅享高速全球网络', 'Enjoy fast global network'),
      onTap: () => openPortal('/pricing'),
    ),
  ]);
}

// ── 新版本提示 banner（#2）────────────────────────────────────────────────────
class _UpdateBanner extends StatelessWidget {
  final String version;
  const _UpdateBanner({required this.version});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.mirrorspeed.com/download'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        width: double.infinity,
        margin:  const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        kBrand.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: kBrand.withOpacity(0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.system_update_rounded, color: kBrand, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('发现新版本 v$version，点击前往下载更新', 'New version v$version available — tap to update'),
            style: const TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.w500))),
          Text(tr('更新 →', 'Update →'), style: const TextStyle(color: kBrand, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

// ── 全局通告 banner（#2，运营在 Supabase 下发）────────────────────────────────
class _AnnouncementBanner extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnnouncementBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '') as String;
    final body  = (data['body']  ?? '') as String;
    final level = (data['level'] ?? 'info') as String;
    final color = level == 'warning' ? Colors.amber
                : level == 'critical' ? kDanger
                : kBrand;
    final url   = data['url'] as String?;
    final w = Container(
      width: double.infinity,
      margin:  const EdgeInsets.only(top: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.campaign_rounded, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty)
            Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(body, style: TextStyle(color: color.withOpacity(0.9), fontSize: 12)),
            ),
        ])),
      ]),
    );
    if (url != null && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: w,
      );
    }
    return w;
  }
}

// ── 订阅到期提醒 banner ───────────────────────────────────────────────────────
class _ExpiryBanner extends StatelessWidget {
  final int days;
  const _ExpiryBanner({required this.days});

  @override
  Widget build(BuildContext context) {
    final isUrgent = days <= 2;
    final color    = isUrgent ? kDanger : Colors.amber;
    final icon     = isUrgent
        ? Icons.warning_rounded
        : Icons.access_time_rounded;
    final text     = days == 0
        ? tr('您的订阅今天到期，请尽快续费', 'Your subscription expires today — please renew')
        : tr('您的订阅将在 $days 天后到期', 'Your subscription expires in $days days');

    return GestureDetector(
      onTap: () => openPortal('/dashboard/billing'),
      child: Container(
        width: double.infinity,
        margin:  const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Text(tr('续费 →', 'Renew →'),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

// ── 智能 / 全局 模式切换 Toggle ──────────────────────────────────────────────
class _RoutingModeToggle extends StatelessWidget {
  final RoutingMode              mode;
  final ValueChanged<RoutingMode> onChanged;
  const _RoutingModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        kCard,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _ToggleItem(
          label:    '智能模式',
          subtitle: '按规则代理',
          icon:     Icons.bolt_rounded,
          selected: mode == RoutingMode.smart,
          onTap:    () => onChanged(RoutingMode.smart),
        ),
        _ToggleItem(
          label:    '全局模式',
          subtitle: '所有流量代理',
          icon:     Icons.public_rounded,
          selected: mode == RoutingMode.global,
          onTap:    () => onChanged(RoutingMode.global),
        ),
      ]),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final String       label;
  final String       subtitle;
  final IconData     icon;
  final bool         selected;
  final VoidCallback onTap;
  const _ToggleItem({
    required this.label, required this.subtitle, required this.icon,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = selected ? kBrand : Colors.white.withOpacity(0.4);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color:        selected ? kBrand.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border:       Border.all(color: selected ? kBrand.withOpacity(0.5) : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: activeColor),
                const SizedBox(width: 6),
                Text(label,
                  style: TextStyle(
                    fontSize:   14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:      selected ? Colors.white : Colors.white.withOpacity(0.55),
                  )),
              ]),
              const SizedBox(height: 4),
              Text(subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? kBrand.withOpacity(0.9) : Colors.white.withOpacity(0.35),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

// 今日免费流量已达上限：提示明日刷新 / 升级会员，并可看广告继续使用。
class _QuotaSuspendedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kGold.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kGold.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline_rounded, color: kGold, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('今日流量已达上限', "Today's data limit reached"),
                style: const TextStyle(color: kGold, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            tr('已超出当日免费流量阈值。请明日自动刷新，或升级会员享不限流量；也可观看广告后继续使用。',
               'You have reached the daily free-data threshold. It resets tomorrow — or upgrade to Premium for unlimited data. You can also watch an ad to keep using the service.'),
            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.push('/vip'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kGold,
                  side: BorderSide(color: kGold.withOpacity(0.6)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(tr('升级会员', 'Upgrade')),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: _AdExtendButton(compact: true)),
          ]),
        ],
      ),
    );
  }
}
