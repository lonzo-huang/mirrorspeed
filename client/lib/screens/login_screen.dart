import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../brand.dart';
import '../theme.dart';

enum _LoginMethod { otp, password, google }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _pwCtrl    = TextEditingController();

  _LoginMethod _method = _LoginMethod.otp;
  bool _loading  = false;
  bool _sent     = false;   // OTP：是否已发送验证码，进入第二步
  bool _signUp   = false;   // 密码：登录 / 注册
  bool _obscure  = true;
  String? _error;
  String? _notice;          // 成功类提示（如注册确认邮件已发送）

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  void _switchMethod(_LoginMethod m) {
    if (_method == m) return;
    setState(() { _method = m; _error = null; _notice = null; });
  }

  // ── OTP ───────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithEmail(email);
      setState(() { _sent = true; });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
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
    } catch (e) {
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

  // ── 密码 ──────────────────────────────────────────────────────
  Future<void> _passwordSubmit() async {
    final email = _emailCtrl.text.trim();
    final pw    = _pwCtrl.text;
    if (email.isEmpty) { setState(() => _error = tr('请输入邮箱', 'Enter your email')); return; }
    if (pw.length < 6) { setState(() => _error = tr('密码至少 6 位', 'Password must be at least 6 chars')); return; }
    setState(() { _loading = true; _error = null; _notice = null; });
    try {
      final auth = context.read<AuthProvider>();
      if (_signUp) {
        await auth.signUpWithPassword(email, pw);
        setState(() {
          _signUp = false;
          _notice = tr('注册成功！确认邮件已发送，请查收后再登录',
                       'Signed up! Check your email to confirm, then sign in');
        });
      } else {
        await auth.signInWithPassword(email, pw);
        // 成功后 onAuthStateChange 自动跳转
      }
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  // ── Google ────────────────────────────────────────────────────
  Future<void> _googleLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      await context.read<AuthProvider>().signInWithGoogle();
      if (!kIsWeb && Platform.isWindows) {
        setState(() { _error = null; _loading = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('浏览器已打开，请在浏览器中完成 Google 登录后自动返回',
                            'Browser opened — finish Google sign-in there and you will return automatically')),
            duration: const Duration(seconds: 8),
          ));
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 返回主页（登录是可选入口，不是墙；未登录也能回主页用共享节点等）。
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.go('/home'),
                ),
              ),
              const SizedBox(height: 8),
              // ── Logo ────────────────────────────────────────────
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [msNow.brand, kBrandDark]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: msNow.brand.withOpacity(0.4), blurRadius: 24, offset: Offset(0, 6))],
                  ),
                  child: Icon(Icons.shield_rounded, size: 36, color: msNow.textPrimary),
                ),
              ),
              const SizedBox(height: 24),
              Center(child: Text(Brand.appName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Center(child: Text(tr('高速安全，全球加速', 'Fast, secure, worldwide'),
                  style: TextStyle(color: msNow.textSecondary.withOpacity(0.5), fontSize: 15))),
              const SizedBox(height: 36),

              // ── 登录方式标签 ─────────────────────────────────────
              _MethodTabs(current: _method, onTap: _loading ? null : _switchMethod),
              const SizedBox(height: 24),

              // ── 各方式内容 ───────────────────────────────────────
              if (_method == _LoginMethod.otp)       _buildOtp(),
              if (_method == _LoginMethod.password)  _buildPassword(),
              if (_method == _LoginMethod.google)    _buildGoogle(),

              // ── 提示 / 错误 ──────────────────────────────────────
              if (_notice != null) ...[
                const SizedBox(height: 14),
                _Banner(text: _notice!, color: kSuccess),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _Banner(text: _error!, color: kDanger),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── 验证码方式 ─────────────────────────────────────────────────
  Widget _buildOtp() {
    if (!_sent) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller:   _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect:  false,
          enabled:      !_loading,
          decoration: InputDecoration(
            hintText:   tr('输入邮箱地址', 'Enter your email'),
            prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
          ),
          onSubmitted: (_) => _sendOtp(),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _loading ? null : _sendOtp,
          child: _loading
              ? const _BtnSpinner()
              : Text(tr('发送验证码', 'Send code')),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            style: TextStyle(color: msNow.textSecondary.withOpacity(0.55), fontSize: 13, height: 1.5),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      TextField(
        controller:      _otpCtrl,
        keyboardType:    TextInputType.number,
        textAlign:       TextAlign.center,
        maxLength:       6,
        autofocus:       true,
        enabled:         !_loading,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 12, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText:       '──────',
          hintStyle:      TextStyle(color: msNow.textSecondary.withOpacity(0.15), letterSpacing: 10),
          counterText:    '',
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onSubmitted: (_) => _verifyOtp(),
        onChanged: (v) { if (v.length == 6) _verifyOtp(); },
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _loading ? null : _verifyOtp,
        child: _loading ? const _BtnSpinner() : Text(tr('验证登录', 'Verify & sign in')),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(
          onPressed: _loading ? null : _sendOtp,
          child: Text(tr('重新发送', 'Resend'), style: const TextStyle(fontSize: 13)),
        ),
        Text('·', style: TextStyle(color: msNow.textSecondary.withOpacity(0.3))),
        TextButton(
          onPressed: _loading ? null : () => setState(() { _sent = false; _otpCtrl.clear(); _error = null; }),
          child: Text(tr('换个邮箱', 'Change email'), style: const TextStyle(fontSize: 13)),
        ),
      ]),
    ]);
  }

  // ── 密码方式 ───────────────────────────────────────────────────
  Widget _buildPassword() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller:   _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        autocorrect:  false,
        enabled:      !_loading,
        decoration: InputDecoration(
          hintText:   tr('邮箱地址', 'Email'),
          prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _pwCtrl,
        obscureText: _obscure,
        enabled:     !_loading,
        decoration: InputDecoration(
          hintText:   tr('密码（至少 6 位）', 'Password (min 6)'),
          prefixIcon: const Icon(Icons.lock_outline_rounded, color: Colors.grey),
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: Colors.grey, size: 20),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (_) => _passwordSubmit(),
      ),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _loading ? null : _passwordSubmit,
        child: _loading
            ? const _BtnSpinner()
            : Text(_signUp ? tr('注册', 'Sign up') : tr('登录', 'Sign in')),
      ),
      const SizedBox(height: 6),
      Center(child: TextButton(
        onPressed: _loading ? null : () => setState(() { _signUp = !_signUp; _error = null; _notice = null; }),
        child: Text(
          _signUp ? tr('已有账号？去登录', 'Have an account? Sign in')
                  : tr('没有账号？去注册', 'No account? Sign up'),
          style: const TextStyle(fontSize: 13)),
      )),
    ]);
  }

  // ── Google 方式 ────────────────────────────────────────────────
  Widget _buildGoogle() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(tr('使用你的 Google 账号一键登录', 'Sign in instantly with your Google account'),
            textAlign: TextAlign.center,
            style: TextStyle(color: msNow.textSecondary.withOpacity(0.5), fontSize: 13)),
      ),
      _OAuthButton(
        onTap:  _loading ? null : _googleLogin,
        icon:   Icons.g_mobiledata_rounded,
        label:  tr('使用 Google 账号登录', 'Sign in with Google'),
      ),
    ]);
  }
}

// ── 三段式方式标签 ────────────────────────────────────────────────
class _MethodTabs extends StatelessWidget {
  final _LoginMethod current;
  final void Function(_LoginMethod)? onTap;
  const _MethodTabs({ required this.current, required this.onTap });

  @override
  Widget build(BuildContext context) {
    Widget seg(_LoginMethod m, String label) {
      final sel = current == m;
      return Expanded(child: GestureDetector(
        onTap: onTap == null ? null : () => onTap!(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? msNow.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            color: sel ? msNow.textPrimary : msNow.textSecondary.withOpacity(0.55),
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500, fontSize: 14)),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: msNow.card, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        seg(_LoginMethod.otp,      tr('验证码', 'Code')),
        seg(_LoginMethod.password, tr('密码', 'Password')),
        seg(_LoginMethod.google,   'Google'),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  const _Banner({ required this.text, required this.color });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(10),
      border:       Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 13), textAlign: TextAlign.center),
  );
}

class _BtnSpinner extends StatelessWidget {
  const _BtnSpinner();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: msNow.textPrimary));
}

class _OAuthButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  const _OAuthButton({ this.onTap, required this.icon, required this.label });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        msNow.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22, color: msNow.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}
