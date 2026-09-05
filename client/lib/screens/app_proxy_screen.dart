import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import '../services/app_proxy_store.dart';
import '../brand.dart';
import '../theme.dart';

/// 分应用代理设置页。
/// - Android：列已安装 App，按包名分流（sing-box include/exclude_package）。
/// - Windows：列正在运行的进程，按进程名(exe)分流（sing-box process_name 路由规则）。
class AppProxyScreen extends StatefulWidget {
  const AppProxyScreen({super.key});
  @override
  State<AppProxyScreen> createState() => _AppProxyScreenState();
}

/// 通用列表项：id 是存进 AppProxyStore 的标识（Android=包名 / Windows=exe 名）。
class _ProxyItem {
  final String id;         // com.google.android.youtube  /  chrome.exe
  final String name;       // 展示名（App 名 / 窗口标题）
  final String sub;        // 副标题（包名 / exe 名）
  final Uint8List? icon;   // 仅 Android 有
  const _ProxyItem(this.id, this.name, this.sub, {this.icon});
}

class _AppProxyScreenState extends State<AppProxyScreen> {
  bool _enabled = true;
  String _mode = 'white';          // white=白名单 / black=黑名单
  Set<String> _selected = {};
  List<_ProxyItem> _items = [];
  bool _loading = true;
  String _query = '';

  bool get _isWin => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _enabled  = await AppProxyStore.loadEnabled();
    _mode     = await AppProxyStore.loadMode();
    _selected = await AppProxyStore.loadPkgs();
    _items    = _isWin ? await _loadWindowsProcesses() : await _loadAndroidApps();
    if (mounted) setState(() => _loading = false);
  }

  Future<List<_ProxyItem>> _loadAndroidApps() async {
    try {
      // 包含系统 App（Chrome/系统浏览器/YouTube 等常是系统预装）。
      final apps = await InstalledApps.getInstalledApps(false, true);
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return apps
          .map((a) => _ProxyItem(a.packageName, a.name, a.packageName,
              icon: a.icon as Uint8List?))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 枚举正在运行、且有可见窗口的进程（= 用户可感知的应用），按 exe 去重。
  Future<List<_ProxyItem>> _loadWindowsProcesses() async {
    try {
      final res = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-Command',
        // 强制 UTF-8 输出，避免中文窗口标题在默认代码页下变乱码。
        "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; "
        "Get-Process | Where-Object { \$_.MainWindowTitle } | "
        "Select-Object ProcessName, MainWindowTitle, Path | ConvertTo-Json -Compress",
      ], stdoutEncoding: utf8);
      if (res.exitCode != 0) return [];
      final out = (res.stdout as String).trim();
      if (out.isEmpty) return [];
      final decoded = jsonDecode(out);
      final list = decoded is List ? decoded : [decoded];
      final byExe = <String, _ProxyItem>{};
      for (final e in list) {
        if (e is! Map) continue;
        final pname = (e['ProcessName'] ?? '').toString();
        final path  = (e['Path'] ?? '').toString();
        final title = (e['MainWindowTitle'] ?? '').toString();
        // exe 名：优先取真实路径的文件名，否则进程名 + .exe。
        String exe = path.isNotEmpty
            ? path.replaceAll('/', '\\').split('\\').last
            : (pname.isEmpty ? '' : '$pname.exe');
        if (exe.isEmpty) continue;
        exe = exe.toLowerCase();
        final display = title.trim().isNotEmpty ? title.trim() : pname;
        byExe.putIfAbsent(exe, () => _ProxyItem(exe, display, exe));
      }
      final items = byExe.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshWin() async {
    setState(() => _loading = true);
    _items = await _loadWindowsProcesses();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() => AppProxyStore.save(enabled: _enabled, mode: _mode, pkgs: _selected);

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    bool match(_ProxyItem a) => q.isEmpty ||
        a.name.toLowerCase().contains(q) || a.sub.toLowerCase().contains(q);
    // 已选中的项（含名单里但当前进程列表没枚举到的，Windows 用占位行展示）。
    final visibleIds = _items.map((e) => e.id).toSet();
    final chosen = _items.where((a) => _selected.contains(a.id) && match(a)).toList();
    final missing = _selected
        .where((id) => !visibleIds.contains(id) &&
            (q.isEmpty || id.toLowerCase().contains(q)))
        .map((id) => _ProxyItem(id, id, id))
        .toList();
    final rest = _items.where((a) => !_selected.contains(a.id) && match(a)).toList();

    final rows = <dynamic>[];
    rows.add(tr('已选中（${chosen.length + missing.length}）',
        'Selected (${chosen.length + missing.length})'));
    if (chosen.isEmpty && missing.isEmpty) rows.add('__empty__');
    rows.addAll(missing);   // 名单里但未在运行（Windows）
    rows.addAll(chosen);
    rows.add(_isWin ? tr('正在运行的应用', 'Running apps') : tr('未选中', 'Not selected'));
    rows.addAll(rest);

    return Scaffold(
      backgroundColor: msNow.bg,
      appBar: AppBar(
        title: Text(tr('分应用代理', 'Per-app proxy')),
        backgroundColor: msNow.bg, surfaceTintColor: Colors.transparent,
        actions: [
          if (_isWin)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: tr('刷新进程', 'Refresh'),
              onPressed: _loading ? null : _refreshWin,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _header(),
              const Divider(height: 1),
              Expanded(child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final row = rows[i];
                  if (row == '__empty__') {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                          _isWin
                              ? tr('暂无，勾选下方正在运行的应用加入',
                                    'None yet — check a running app below')
                              : tr('暂无，勾选下方应用加入', 'None yet — check apps below'),
                          style: TextStyle(fontSize: 12, color: msNow.textSecondary.withOpacity(0.35))),
                    );
                  }
                  if (row is String) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text(row, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: msNow.textSecondary.withOpacity(0.5))),
                    );
                  }
                  final a = row as _ProxyItem;
                  final on = _selected.contains(a.id);
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    onChanged: _enabled ? (v) {
                      setState(() {
                        if (v == true) { _selected.add(a.id); }
                        else { _selected.remove(a.id); }
                      });
                      _persist();
                    } : null,
                    secondary: (a.icon != null)
                        ? Image.memory(a.icon!, width: 34, height: 34)
                        : Icon(_isWin ? Icons.desktop_windows_outlined : Icons.android),
                    title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(a.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              )),
            ]),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          onChanged: (v) { setState(() => _enabled = v); _persist(); },
          title: Text(tr('启用分应用代理', 'Enable per-app proxy'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          subtitle: Text(
              _isWin
                  ? tr('免费节点按进程分流；关闭则所有流量走 VPN',
                        'Free nodes route by process; off = all via VPN')
                  : tr('仅智能模式生效；关闭则所有 App 按智能规则走', 'Smart mode only'),
              style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(height: 6),
        // 白/黑名单切换
        Opacity(
          opacity: _enabled ? 1 : 0.4,
          child: Row(children: [
            _modeChip('white', tr('白名单', 'Whitelist'),
                _isWin ? tr('只有勾选的应用走 VPN', 'Only selected use VPN')
                       : tr('只有勾选的 App 走 VPN', 'Only selected use VPN')),
            const SizedBox(width: 10),
            _modeChip('black', tr('黑名单', 'Blacklist'),
                _isWin ? tr('勾选的应用不走 VPN', 'Selected bypass VPN')
                       : tr('勾选的 App 不走 VPN', 'Selected bypass VPN')),
          ]),
        ),
        if (_isWin) ...[
          const SizedBox(height: 8),
          Text(
            tr('仅显示正在运行且有窗口的应用；如没看到，先打开该应用再点右上角刷新。',
               'Shows running apps with a window. Don\'t see it? Open the app, then Refresh.'),
            style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.4))),
        ],
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: _isWin ? tr('搜索应用/进程', 'Search apps') : tr('搜索应用', 'Search apps'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }

  Widget _modeChip(String m, String label, String desc) {
    final sel = _mode == m;
    return Expanded(child: GestureDetector(
      onTap: _enabled ? () { setState(() => _mode = m); _persist(); } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? msNow.brand.withOpacity(0.18) : msNow.textSecondary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? msNow.brand : msNow.textSecondary.withOpacity(0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: sel ? msNow.brand : msNow.textSecondary)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 10, color: msNow.textSecondary.withOpacity(0.4))),
        ]),
      ),
    ));
  }
}
