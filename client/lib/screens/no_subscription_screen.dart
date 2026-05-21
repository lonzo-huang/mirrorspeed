import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../env.dart';
import '../theme.dart';

class NoSubscriptionScreen extends StatelessWidget {
  const NoSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 72, color: Colors.white38),
              const SizedBox(height: 24),
              const Text('尚未开通服务', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('请前往 MirrorSpeed 官网订阅后再使用客户端',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5), height: 1.6)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('前往订阅'),
                onPressed: () => launchUrl(Uri.parse('$kApiBase/dashboard/billing')),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () async {
                  await context.read<AuthProvider>().refreshConfigs();
                },
                child: const Text('已完成订阅，刷新状态'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.read<AuthProvider>().signOut(),
                child: Text('退出登录', style: TextStyle(color: Colors.white.withOpacity(0.4))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
