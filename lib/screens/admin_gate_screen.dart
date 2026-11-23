import 'package:flutter/material.dart';

import '../main.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import 'admin_screen.dart';

/// The `/admin` route (web only): the admin panel, securely locked
/// behind an email + password sign-in and a strict `users.is_admin`
/// check. There is no entry to this page from the app UI — it only
/// opens at the `/admin` URL.
class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});

  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
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
    _passwordController.dispose();
    super.dispose();
  }

  /// A persisted admin session skips the form; a persisted non-admin
  /// session is signed out so the form starts clean.
  Future<void> _checkSession() async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final admin = await AdminService.instance.isAdmin(uid);
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

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your admin email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.loginWithEmail(
        email: email,
        password: password,
      );
      final uid = AuthService.instance.currentUid;
      if (uid == null) throw Exception('Sign-in failed.');
      final admin = await AdminService.instance.isAdmin(uid);
      if (!mounted) return;
      if (!admin) {
        await AuthService.instance.signOut();
        setState(() => _error = 'This account is not an admin.');
        return;
      }
      setState(() => _isAdmin = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isAdmin = false;
      _error = null;
      _passwordController.clear();
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
                  'Only the admin account can open this page. The panel is not linked from the app.',
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
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: jimFieldDecoration(
                    dark: isDark,
                    hint: 'Password',
                  ),
                  onSubmitted: (_) => _signIn(),
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
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
