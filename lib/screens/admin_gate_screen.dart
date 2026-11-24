import 'package:flutter/material.dart';

import '../main.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';
import 'otp_screen.dart';

/// The `/admin` route (web only): the admin panel, securely locked
/// behind an email + 6-digit code sign-in and a strict
/// `users.is_admin` check. There is no entry to this page from the
/// app UI — it only opens at the `/admin` URL.
class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});

  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  final _emailController = TextEditingController();
  bool _busy = false;
  bool _checking = true;
  bool _isAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// A persisted admin session skips the form; a persisted non-admin
  /// session is signed out so the form starts clean.
  Future<void> _checkSession() async {
    if (!AuthService.instance.isSignedIn) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final admin = AdminService.instance.isAdmin();
    if (!mounted) return;
    if (!admin) {
      await AuthService.instance.signOut();
      setState(() {
        _checking = false;
        _error = 'This account is not an admin.';
      });
      return;
    }
    setState(() {
      _checking = false;
      _isAdmin = true;
    });
  }

  /// After the code is verified: admins go in, everyone else is
  /// signed straight back out.
  Future<void> _afterVerified() async {
    if (!AdminService.instance.isAdmin()) {
      await AuthService.instance.signOut();
      if (mounted) {
        setState(() => _error = 'This account is not an admin.');
      }
      return;
    }
    if (mounted) setState(() => _isAdmin = true);
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid admin email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendLoginCode(email: email);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AuthService.friendlyError(e);
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => OtpScreen(
          email: email,
          onVerified: _afterVerified,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isAdmin = false;
      _error = null;
      _emailController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_isAdmin) {
      return AdminScreen(onSignOut: _signOut);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.shield, size: 44, color: JimColors.rose),
                const SizedBox(height: 16),
                Text(
                  'Admin sign in',
                  style: base.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Only the admin account can open this page. We will send a 6-digit code to your email. The panel is not linked from the app.',
                  style: base.copyWith(
                    fontSize: 14,
                    color: muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: jimFieldDecoration(
                    dark: isDark,
                    hint: 'Admin email',
                  ),
                  onSubmitted: (_) => _sendCode(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: base.copyWith(fontSize: 14, color: Colors.red),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _sendCode,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
