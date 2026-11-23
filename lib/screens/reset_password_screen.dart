import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';

/// Set-a-new-password screen, shown when the user opens the reset
/// link from their email (Supabase emits passwordRecovery and the
/// recovery session is already valid). After a successful update the
/// user is signed in, so [onDone] returns to the tracker.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _busy = false;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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

  Future<void> _save() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 6) {
      await _showMessage(
        title: 'Password too short',
        message: 'Your new password must be at least 6 characters.',
      );
      return;
    }
    if (password != confirm) {
      await _showMessage(
        title: 'Passwords do not match',
        message: 'Type the same new password in both fields.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthService.instance.updatePassword(newPassword: password);
      if (!mounted) return;
      setState(() => _busy = false);
      await _showMessage(
        title: 'Password updated',
        message: 'Your password has been changed. You are signed in now.',
      );
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showMessage(
        title: 'Something went wrong',
        message: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Text(
              'Choose a new password',
              style: base.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'You opened the reset link from your email. '
              'Type a new password below.',
              style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: jimFieldDecoration(
                dark: isDark,
                hint: 'New password',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: jimFieldDecoration(
                dark: isDark,
                hint: 'Confirm new password',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_busy ? 'Please wait…' : 'Save new password'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
