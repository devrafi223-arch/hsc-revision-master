import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';

/// Email + 6-digit code login, Material only.
///
/// There is no password and no Google sign-in: the user enters an
/// email, taps "Send code", types the 6-digit code from the mail, and
/// a 7-day JWT session starts. Register and login are the same flow —
/// the code creates the account on first use.
///
/// There is deliberately NO "Continue offline" escape here (Rafi):
/// login is mandatory; offline is only shown after login, when the
/// device loses internet (the "Offline — will sync" pill).
class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome'),
      ),
      body: const SafeArea(
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
  bool _busy = false;
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _goHome() {
    // After sign-in the app-level auth notifier rebuilds to HomeScreen.
    // Popping returns from a pushed AuthScreen (e.g. Profile tab); on
    // the root gate there is nothing to pop and the notifier drives it.
    Navigator.of(context).pop();
  }

  Future<void> _showError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      await _showError('Please enter a valid email address.');
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.instance.sendLoginCode(email: email);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(AuthService.friendlyError(e));
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OtpScreen(
          email: email,
          onVerified: _goHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Text(
          'Welcome back',
          style: base.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your email and we will send you a 6-digit code to log in. '
          'New here? The same code creates your account.',
          style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: jimFieldDecoration(
            dark: isDark,
            hint: 'Email',
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(_busy ? 'Please wait…' : 'Send code'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Only Gmail, Hotmail, Outlook, and Yahoo emails are allowed.',
          style: base.copyWith(fontSize: 13, color: muted, height: 1.45),
        ),
      ],
    );
  }
}
