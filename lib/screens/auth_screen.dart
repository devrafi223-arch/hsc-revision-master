import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

/// Email + OTP + Google sign-in, Cupertino only.
///
/// Register flow (matches AuthService): send OTP -> enter the 6-digit
/// code -> verify -> create the account with [AuthService.registerWithEmail].
/// While Firebase is not configured the service stores a demo code in
/// SharedPreferences (`demo-otp-<email>`); the OTP step shows it labelled
/// as a demo code, since no email can actually be sent yet.
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Welcome'),
      ),
      child: const SafeArea(
        child: _AuthForm(),
      ),
    );
  }
}

class _AuthForm extends StatefulWidget {
  const _AuthForm();

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  bool _isRegister = false;
  bool _otpStep = false;
  bool _busy = false;
  String? _demoCode;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      CupertinoPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Something went wrong'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      await _showError('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      await _showError('Password must be at least 6 characters.');
      return;
    }
    if (_isRegister && name.isEmpty) {
      await _showError('Please enter your name.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isRegister) {
        // OTP first: the code is verified, then the account is created.
        await AuthService.instance.sendOtp(email);
        String? demoCode;
        if (!AuthService.instance.isAvailable) {
          final prefs = await SharedPreferences.getInstance();
          demoCode = prefs.getString('demo-otp-$email');
        }
        if (!mounted) return;
        setState(() {
          _otpStep = true;
          _demoCode = demoCode;
          _busy = false;
        });
      } else {
        await AuthService.instance.loginWithEmail(
          email: email,
          password: password,
        );
        if (!mounted) return;
        _goHome();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(e.toString());
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final code = _otpController.text.trim();
    if (code.length != 6) {
      await _showError('Enter the 6-digit code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await AuthService.instance.verifyOtp(email, code);
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        await _showError(
          'That code did not match or has expired. Ask for a new one.',
        );
        return;
      }
      await AuthService.instance.registerWithEmail(
        email: email,
        password: _passwordController.text,
        name: _nameController.text.trim(),
      );
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(e.toString());
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _busy = true);
    try {
      await AuthService.instance.signInWithGoogle();
      if (!mounted) return;
      _goHome();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final base = CupertinoTheme.of(context).textTheme.textStyle;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final online = AuthService.instance.isAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        if (!online)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: JimColors.rose.withValues(alpha: isDark ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: JimColors.rose.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Online features need Firebase setup — you can still use the tracker offline.',
                  style: base.copyWith(fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _goHome,
                  child: const Text('Continue offline'),
                ),
              ],
            ),
          ),
        if (!online) const SizedBox(height: 24),
        Text(
          _otpStep
              ? 'Check your email'
              : _isRegister
                  ? 'Create your account'
                  : 'Welcome back',
          style: base.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _otpStep
              ? 'Enter the 6-digit code sent to ${_emailController.text.trim()}.'
              : _isRegister
                  ? 'Register with email, verify the code, and your progress syncs everywhere.'
                  : 'Sign in to sync your progress and join the community.',
          style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        if (_otpStep) ...[
          if (_demoCode != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? JimColors.darkBg : JimColors.paper,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? JimColors.darkLine : JimColors.line,
                ),
              ),
              child: Text(
                'Demo code (no email configured yet): $_demoCode',
                style: base.copyWith(fontSize: 15, height: 1.45),
              ),
            ),
          CupertinoTextField(
            controller: _otpController,
            placeholder: '6-digit code',
            keyboardType: TextInputType.number,
            maxLength: 6,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? JimColors.darkSurface : JimColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? JimColors.darkLine : JimColors.line,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              borderRadius: BorderRadius.circular(14),
              onPressed: _busy ? null : _verifyOtp,
              child: Text(_busy ? 'Verifying…' : 'Verify & create account'),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _otpStep = false;
                      _demoCode = null;
                    }),
            child: const Text('Back'),
          ),
        ] else ...[
          CupertinoSlidingSegmentedControl<int>(
            groupValue: _isRegister ? 1 : 0,
            backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
            thumbColor: isDark ? JimColors.darkSurface : JimColors.card,
            children: const {
              0: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Login'),
              ),
              1: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Register'),
              ),
            },
            onValueChanged: (index) {
              if (index != null) setState(() => _isRegister = index == 1);
            },
          ),
          const SizedBox(height: 20),
          if (_isRegister) ...[
            CupertinoTextField(
              controller: _nameController,
              placeholder: 'Your name',
              textCapitalization: TextCapitalization.words,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? JimColors.darkSurface : JimColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? JimColors.darkLine : JimColors.line,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          CupertinoTextField(
            controller: _emailController,
            placeholder: 'Email',
            keyboardType: TextInputType.emailAddress,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? JimColors.darkSurface : JimColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? JimColors.darkLine : JimColors.line,
              ),
            ),
          ),
          const SizedBox(height: 12),
          CupertinoTextField(
            controller: _passwordController,
            placeholder: 'Password',
            obscureText: true,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? JimColors.darkSurface : JimColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? JimColors.darkLine : JimColors.line,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              borderRadius: BorderRadius.circular(14),
              onPressed: _busy ? null : _submit,
              child: Text(
                _busy
                    ? 'Please wait…'
                    : _isRegister
                        ? 'Send code'
                        : 'Log in',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: isDark ? JimColors.darkLine : JimColors.line,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: base.copyWith(fontSize: 14, color: muted),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: isDark ? JimColors.darkLine : JimColors.line,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: isDark ? JimColors.darkSurface : JimColors.card,
              borderRadius: BorderRadius.circular(14),
              onPressed: _busy ? null : _signInWithGoogle,
              child: const Text('Continue with Google'),
            ),
          ),
        ],
      ],
    );
  }
}
