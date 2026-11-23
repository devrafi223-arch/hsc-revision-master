import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/supabase_init.dart';

/// Email + password + Google sign-in, Material only.
///
/// Register flow: create the account directly with
/// [AuthService.registerWithEmail] (email + password + name). No email-code
/// verification step.
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

/// Forgot-password dialog: asks for the account email and sends the
/// Supabase reset link. Errors stay inside the dialog; on success it
/// closes and the parent shows the "check your email" message.
class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.onSent});

  final VoidCallback onSent;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _busy = false;
  String? _error;
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSent();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      title: const Text('Reset password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your account email and we will send you a reset link.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: jimFieldDecoration(dark: isDark, hint: 'Email'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Please wait…' : 'Send reset link'),
        ),
      ],
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
  bool _busy = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _goHome() {
    // After sign-in the app-level auth stream rebuilds to HomeScreen.
    // Popping returns from a pushed AuthScreen (e.g. Profile tab); on
    // the root gate there is nothing to pop and the stream drives it.
    // There is deliberately NO "Continue offline" escape here (Rafi):
    // login is mandatory; offline is only shown after login, when the
    // device loses internet (the "Offline — will sync" pill).
    Navigator.of(context).pop();
  }

  Future<void> _tryAgain() async {
    setState(() => _busy = true);
    await SupabaseInit.retry();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _showMessage({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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

  Future<void> _showError(String message) async {
    await _showMessage(title: 'Something went wrong', message: message);
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
        await AuthService.instance.registerWithEmail(
          email: email,
          password: password,
          name: name,
        );
        if (!mounted) return;
        setState(() => _busy = false);
        if (AuthService.instance.signedIn) {
          // Email auto-confirmed (or already confirmed): session
          // exists, go straight in.
          _goHome();
          return;
        }
        // Email confirmation is required, so there is no session yet
        // and the auth stream will NOT rebuild: say so clearly and
        // switch to the Login tab. (Before this fix the button just
        // stayed stuck on "Please wait…" with no message at all.)
        setState(() => _isRegister = false);
        await _showMessage(
          title: 'Account created!',
          message: 'Check your email for the confirmation link, '
              'then log in here.',
        );
      } else {
        await AuthService.instance.loginWithEmail(
          email: email,
          password: password,
        );
        if (!mounted) return;
        setState(() => _busy = false);
        _goHome();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(e.toString());
    }
  }

  Future<void> _forgotPassword() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ForgotPasswordDialog(
        onSent: () => _showMessage(
          title: 'Reset link sent',
          message: 'Check your email for the password reset link.',
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
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
                  SupabaseInit.lastError == null
                      ? 'Online features need Supabase setup — you can still use the tracker offline.'
                      : 'Online features unavailable: ${SupabaseInit.lastError}',
                  style: base.copyWith(fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _tryAgain,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Try again'),
                  ),
                ),
              ],
            ),
          ),
        if (!online) const SizedBox(height: 24),
        Text(
          _isRegister ? 'Create your account' : 'Welcome back',
          style: base.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _isRegister
              ? 'Register with email and your progress syncs everywhere.'
              : 'Sign in to sync your progress and join the community.',
          style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(
                value: 0,
                label: Text('Login'),
              ),
              ButtonSegment<int>(
                value: 1,
                label: Text('Register'),
              ),
            ],
            selected: {_isRegister ? 1 : 0},
            onSelectionChanged: (selection) {
              setState(() => _isRegister = selection.first == 1);
            },
            style: SegmentedButton.styleFrom(
              backgroundColor: isDark ? JimColors.darkLine : JimColors.line,
              selectedBackgroundColor:
                  isDark ? JimColors.darkSurface : JimColors.card,
              selectedForegroundColor:
                  isDark ? JimColors.darkText : JimColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_isRegister) ...[
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: jimFieldDecoration(
              dark: isDark,
              hint: 'Your name',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: jimFieldDecoration(
            dark: isDark,
            hint: 'Email',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: jimFieldDecoration(
            dark: isDark,
            hint: 'Password',
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
            child: Text(
              _busy
                  ? 'Please wait…'
                  : _isRegister
                      ? 'Create account'
                      : 'Log in',
            ),
          ),
        ),
        if (!_isRegister) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _forgotPassword,
              child: const Text('Forgot password?'),
            ),
          ),
        ],
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
          child: FilledButton.tonal(
            onPressed: _busy ? null : _signInWithGoogle,
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? JimColors.darkSurface : JimColors.card,
              foregroundColor: isDark ? JimColors.darkText : JimColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Continue with Google'),
          ),
        ),
      ],
    );
  }
}
