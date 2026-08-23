import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import '../services/app_proxy_store.dart';
import '../brand.dart';
import '../theme.dart';

/// 分应用代理（智能模式黑白名单）设置页。
class AppProxyScreen extends StatefulWidget {
  const AppProxyScreen({super.key});
  @override
  State<AppProxyScreen> createState() => _AppProxyScreenState();
}

class _AppProxyScreenState extends State<AppProxyScreen> {
  bool _enabled = true;
  String _mode = 'white';          // white=白名单 / black=黑名单
  Set<String> _selected = {};
  List<AppInfo> _apps = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _enabled  = await AppProxyStore.loadEnabled();
    _mode     = await AppProxyStore.loadMode();
    _selected = await AppProxyStore.loadPkgs();
    try {
      final apps = await InstalledApps.getInstalledApps(true, true);   // 排除系统 App，带图标
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _apps = apps;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() => AppProxyStore.save(enabled: _enabled, mode: _mode, pkgs: _selected);

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _apps
        : _apps.where((a) => a.name.toLowerCase().contains(_query.toLowerCase()) ||
            a.packageName.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr('分应用代理', 'Per-app proxy')),
        backgroundColor: kBg, surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _header(),
              const Divider(height: 1),
              Expanded(child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final a = filtered[i];
                  final on = _selected.contains(a.packageName);
                  return CheckboxListTile(
                    dense: true,
                    value: on,
                    onChanged: _enabled ? (v) {
                      setState(() {
                        if (v == true) { _selected.add(a.packageName); }
                        else { _selected.remove(a.packageName); }
                      });
                      _persist();
                    } : null,
                    secondary: (a.icon != null)
                        ? Image.memory(a.icon as Uint8List, width: 34, height: 34)
                        : const Icon(Icons.android),
                    title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(a.packageName, maxLines: 1, overflow: TextOverflow.ellipsis,
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
          subtitle: Text(tr('仅智能模式生效；关闭则所有 App 按智能规则走', 'Smart mode only'),
              style: const TextStyle(fontSize: 11)),
        ),
        const SizedBox(height: 6),
        // 白/黑名单切换
        Opacity(
          opacity: _enabled ? 1 : 0.4,
          child: Row(children: [
            _modeChip('white', tr('白名单', 'Whitelist'), tr('只有勾选的 App 走 VPN', 'Only selected use VPN')),
            const SizedBox(width: 10),
            _modeChip('black', tr('黑名单', 'Blacklist'), tr('勾选的 App 不走 VPN', 'Selected bypass VPN')),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: tr('搜索应用', 'Search apps'),
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
          color: sel ? kBrand.withOpacity(0.18) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: sel ? kBrand : Colors.white.withOpacity(0.1)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: sel ? kBrand : Colors.white70)),
          const SizedBox(height: 2),
          Text(desc, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4))),
        ]),
      ),
    ));
  }
}
