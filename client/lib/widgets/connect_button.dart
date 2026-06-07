import 'package:flutter/material.dart';
import '../providers/vpn_provider.dart';
import '../brand.dart';
import '../theme.dart';

class ConnectButton extends StatelessWidget {
  final VpnStatus status;
  final VoidCallback? onPressed;
  const ConnectButton({ super.key, required this.status, this.onPressed });

  @override
  Widget build(BuildContext context) {
    final (color, shadow, icon, label) = switch (status) {
      VpnStatus.connected      => (kSuccess,  kSuccess,  Icons.shield_rounded,      tr('已连接', 'Connected')),
      VpnStatus.connecting     => (kBrand,    kBrand,    Icons.refresh_rounded,     tr('连接中…', 'Connecting…')),
      VpnStatus.disconnecting  => (Colors.orange, Colors.orange, Icons.refresh_rounded, tr('断开中…', 'Disconnecting…')),
      VpnStatus.error          => (kDanger,   kDanger,   Icons.error_outline_rounded, tr('出错了', 'Error')),
      _                        => (Colors.white70, Colors.white24, Icons.power_settings_new_rounded, tr('点击连接', 'Tap to connect')),
    };

    final isSpinning = status == VpnStatus.connecting || status == VpnStatus.disconnecting;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        width: 160, height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(status == VpnStatus.disconnected ? 0.10 : 0.2),
          border: Border.all(color: color, width: status == VpnStatus.disconnected ? 2.0 : 2.5),
          boxShadow: status != VpnStatus.disconnected
              ? [BoxShadow(color: shadow.withOpacity(0.35), blurRadius: 40, spreadRadius: 4)]
              : [],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          isSpinning
              ? SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3, color: color))
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(icon, key: ValueKey(status), size: 52, color: color),
                ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    );
  }
}
