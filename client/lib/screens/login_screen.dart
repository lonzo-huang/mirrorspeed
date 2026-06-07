import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../brand.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();

  bool    _loading = false;
  bool    _sent    = false;   // 是否已发送验证码，进入第二步
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
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

  Future<void> _verifyOtp() async {
    final token = _otpCtrl.text.trim();
    if (token.length != 6) {
      setState(() { _error = tr('请输入 6 位验证码', 'Enter the 6-digit code'); });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().verifyOtp(_emailCtrl.text.trim(), token);
      // 验证成功后 AuthProvider 内部会更新状态，UI 自动切换
    } catch (e) {
      // verifyOTP 有时会抛异常，但 onAuthStateChange 已同步触发登录成功
      // 此时 session 已存在，忽略这个假错误，GoRouter 会自动跳转
      if (mounted && !context.read<AuthProvider>().isLoggedIn) {
        setState(() {
          _error = tr('验证码错误或已过期，请重试', 'Invalid or expired code, please try again');
          _otpCtrl.clear();
        });
      }
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _googleLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithGoogle();
      // On Windows, the browser opens for OAuth. After the user authenticates,
      // the OS launches the app via mirrorspeed:// deep link and app_links
      // completes the session. Show a hint while waiting.
      if (!kIsWeb && Platform.isWindows) {
        setState(() {
          _error = null;
          _loading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('浏览器已打开，请在浏览器中完成 Google 登录后自动返回',
                              'Browser opened — finish Google sign-in there and you will return automatically')),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
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

              // ── Logo ────────────────────────────────────────────
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
              Center(child: Text(Brand.appName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Center(child: Text(tr('高速安全，全球加速', 'Fast, secure, worldwide'), style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15))),

              const Spacer(),

              // ── 第一步：输入邮箱 ─────────────────────────────────
              if (!_sent) ...[
                TextField(
                  controller:   _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect:  false,
                  enabled:      !_loading,
                  decoration: InputDecoration(
                    hintText:    tr('输入邮箱地址', 'Enter your email'),
                    prefixIcon:  const Icon(Icons.email_outlined, color: Colors.grey),
                  ),
                  onSubmitted: (_) => _sendOtp(),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr('发送验证码', 'Send code')),
                ),

                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Divider(color: Colors.white12)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(tr('或', 'or'), style: TextStyle(color: Colors.white.withOpacity(0.4))),
                  ),
                  const Expanded(child: Divider(color: Colors.white12)),
                ]),
                const SizedBox(height: 20),

                _OAuthButton(
                  onTap:  _loading ? null : _googleLogin,
                  icon:   Icons.g_mobiledata_rounded,
                  label:  tr('使用 Google 账号登录', 'Sign in with Google'),
                ),
              ],

              // ── 第二步：输入验证码 ────────────────────────────────
              if (_sent) ...[
                // 提示卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:        kSuccess.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border:       Border.all(color: kSuccess.withOpacity(0.25)),
                  ),
                  child: Column(children: [
                    const Icon(Icons.mark_email_read_rounded, color: kSuccess, size: 32),
                    const SizedBox(height: 10),
                    Text(tr('验证码已发送', 'Code sent'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      tr('请查收发往 ${_emailCtrl.text} 的邮件\n输入其中的 6 位数字验证码',
                         'Check the email sent to ${_emailCtrl.text}\nand enter the 6-digit code'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13, height: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                // 验证码输入框
                TextField(
                  controller:     _otpCtrl,
                  keyboardType:   TextInputType.number,
                  textAlign:      TextAlign.center,
                  maxLength:      6,
                  autofocus:      true,
                  enabled:        !_loading,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize:      32,
                    fontWeight:    FontWeight.bold,
                    letterSpacing: 12,
                    fontFamily:    'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText:       '──────',
                    hintStyle:      TextStyle(color: Colors.white.withOpacity(0.15), letterSpacing: 10),
                    counterText:    '',   // 隐藏字数计数
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onSubmitted: (_) => _verifyOtp(),
                  onChanged: (v) {
                    // 自动提交：输满 6 位立刻验证（#9，无需再点按钮）
                    if (v.length == 6) _verifyOtp();
                  },
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  onPressed: _loading ? null : _verifyOtp,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr('验证登录', 'Verify & sign in')),
                ),
                const SizedBox(height: 12),

                // 重新发送 / 换邮箱
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(
                    onPressed: _loading ? null : _sendOtp,
                    child: Text(tr('重新发送', 'Resend'), style: const TextStyle(fontSize: 13)),
                  ),
                  Text('·', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() {
                      _sent = false;
                      _otpCtrl.clear();
                      _error = null;
                    }),
                    child: Text(tr('换个邮箱', 'Change email'), style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ],

              // ── 错误提示 ─────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        kDanger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: kDanger.withOpacity(0.3)),
                  ),
                  child: Text(_error!, style: const TextStyle(color: kDanger, fontSize: 13), textAlign: TextAlign.center),
                ),
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
      color:        kCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap:        onTap,
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
