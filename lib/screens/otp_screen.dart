import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/auth_service.dart';

/// Which code flow this screen verifies.
enum OtpPurpose { signup, recovery }

/// 6-digit code entry screen, used for both flows that used to rely
/// on mail LINKS (which show a blank page on a PC browser and cannot
/// open the Windows app):
///
/// * signup — the code from the confirmation mail, verified with
///   [AuthService.verifySignupCode]; on success the session is set.
/// * recovery — the code from the reset mail, verified with
///   [AuthService.verifyRecoveryCode]; on success the app shows the
///   set-new-password screen.
///
/// The mail must contain the code: the Supabase dashboard templates
/// ("Confirm signup" and "Reset Password") must include
/// `{{ .Token }}`. The screen pops itself after a successful verify;
/// the app root then shows the tracker (signup) or the reset screen
/// (recovery, via [AuthService.recoveryPending]).
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
    required this.purpose,
    this.onVerified,
  });

  final String email;
  final OtpPurpose purpose;
  final VoidCallback? onVerified;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _busy = false;
  String? _error;
  String? _info;
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool get _isSignup => widget.purpose == OtpPurpose.signup;

  Future<void> _showError(String message) async {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      await _showError('Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_isSignup) {
        await AuthService.instance.verifySignupCode(
          email: widget.email,
          code: code,
        );
      } else {
        await AuthService.instance.verifyRecoveryCode(
          email: widget.email,
          code: code,
        );
      }
      if (!mounted) return;
      widget.onVerified?.call();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _showError(e.toString());
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      if (_isSignup) {
        await AuthService.instance.resendSignupCode(email: widget.email);
      } else {
        await AuthService.instance
            .sendPasswordResetEmail(email: widget.email);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = 'A new code was sent to ${widget.email}.';
      });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSignup ? 'Confirm your email' : 'Reset password'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            Text(
              'Enter the 6-digit code',
              style: base.copyWith(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to ${widget.email}. '
              'Type it below — no need to open any link.',
              style: base.copyWith(fontSize: 15, color: muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: jimFieldDecoration(
                dark: isDark,
                hint: '6-digit code',
              ),
              style: base.copyWith(
                fontSize: 22,
                letterSpacing: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ],
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(
                _info!,
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _verify,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(_busy ? 'Please wait…' : 'Verify code'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : _resend,
                child: const Text("Didn't get a code? Resend"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
