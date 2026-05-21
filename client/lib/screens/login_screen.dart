import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading  = false;
  bool _sent     = false;
  String? _error;

  @override
  void dispose() { _emailCtrl.dispose(); super.dispose(); }

  Future<void> _sendMagicLink() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithEmail(email);
      setState(() { _sent = true; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _googleLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithGoogle();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _microsoftLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithMicrosoft();
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Logo
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kBrand, kBrandDark]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: kBrand.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.shield_rounded, size: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              const Center(child: Text('MirrorSpeed VPN', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Center(child: Text('高速安全，全球加速', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15))),
              const Spacer(),

              if (_sent) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kSuccess.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kSuccess.withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    const Icon(Icons.mark_email_read_rounded, color: kSuccess, size: 36),
                    const SizedBox(height: 12),
                    const Text('登录链接已发送', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 6),
                    Text('请查收发往 ${_emailCtrl.text} 的邮件，点击其中的链接完成登录', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.6), height: 1.5)),
                  ]),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() { _sent = false; }),
                  child: const Text('换个邮箱重试'),
                ),
              ] else ...[
                // Magic Link
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: '输入邮箱地址',
                    prefixIcon: Icon(Icons.email_outlined, color: Colors.grey),
                  ),
                  onSubmitted: (_) => _sendMagicLink(),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _sendMagicLink,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('发送登录链接'),
                ),

                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('或', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ]),
                const SizedBox(height: 20),

                // OAuth buttons
                _OAuthButton(
                  onTap: _loading ? null : _googleLogin,
                  icon: Icons.g_mobiledata_rounded,
                  label: '使用 Google 账号登录',
                ),
                const SizedBox(height: 10),
                _OAuthButton(
                  onTap: _loading ? null : _microsoftLogin,
                  icon: Icons.window_rounded,
                  label: '使用 Microsoft 账号登录',
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kDanger.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kDanger.withOpacity(0.3)),
                    ),
                    child: Text(_error!, style: const TextStyle(color: kDanger, fontSize: 13), textAlign: TextAlign.center),
                  ),
                ],
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _OAuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  const _OAuthButton({ this.onTap, required this.icon, required this.label });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22, color: Colors.white70),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
