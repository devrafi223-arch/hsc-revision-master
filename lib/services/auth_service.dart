import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'admin_service.dart';
import 'supabase_init.dart';
import 'user_repository.dart';

/// Email + password + Google sign-in, backed by Supabase Auth.
///
/// Every method throws while [SupabaseInit.isOnlineMode] is false.
/// The message names the REAL init failure (SupabaseInit.lastError),
/// not the config placeholder — the old static text blamed
/// supabase_config.dart even when the config was fine and the init
/// itself had crashed (e.g. the StackOverflowError, 2026-11-23).
/// There is no OTP system: registration is email + password only
/// (plus Google Sign-In via Supabase Auth's built-in OAuth — no
/// google_sign_in package).
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  /// True while a password-recovery session is awaiting a new
  /// password. Set by the passwordRecovery auth event (mail-link
  /// flow) and by [verifyRecoveryCode] (code flow); cleared when the
  /// new password is saved or the reset screen is dismissed. The app
  /// root shows the reset screen while this is true.
  static final ValueNotifier<bool> recoveryPending =
      ValueNotifier<bool>(false);

  /// The real reason online is unavailable: the init failure when
  /// there is one, otherwise the missing-config hint.
  static String get _onlineError {
    final cause = SupabaseInit.lastError;
    if (cause != null && cause.isNotEmpty) {
      return 'Online features unavailable: $cause';
    }
    return 'Online features need Supabase setup — replace '
        'lib/supabase_config.dart with your real project values.';
  }

  SupabaseClient get _auth => SupabaseInit.client;

  /// Where Supabase sends the browser after email confirm / Google
  /// sign-in on mobile: a deep link back into the app (supabase_flutter
  /// picks the session up via app_links). Without this, Supabase uses the
  /// project's Site URL — the default is http://localhost:3000, which
  /// refuses to connect on a real phone (seen 2026-11-23: the confirm link
  /// landed on a dead localhost page). The same URL must be listed in the
  /// Supabase dashboard: Auth -> URL Configuration -> Site URL and
  /// Redirect URLs. Web passes null (the web app uses its own URL).
  static const String _authRedirect = 'com.rafi.hscrevise://login-callback';

  /// Emits the signed-in uid, or null when signed out. In local-only mode
  /// emits a single null (there is no account without Supabase).
  Stream<String?> get authStateChanges {
    if (!SupabaseInit.isOnlineMode) return Stream<String?>.value(null);
    return _auth.auth.onAuthStateChange.map(
      (data) => data.session?.user.id,
    );
  }

  String? get currentUid => SupabaseInit.isOnlineMode
      ? _auth.auth.currentUser?.id
      : null;

  bool get signedIn => currentUid != null;

  /// Emits true when a password-recovery link was opened: Supabase
  /// emits [AuthChangeEvent.passwordRecovery] and the app must show
  /// the "set a new password" screen instead of the tracker.
  /// Emits a single false while offline.
  Stream<bool> get passwordRecoveryChanges {
    if (!SupabaseInit.isOnlineMode) return Stream<bool>.value(false);
    return _auth.auth.onAuthStateChange.map(
      (data) => data.event == AuthChangeEvent.passwordRecovery,
    );
  }

  /// False while Supabase is not configured (local-only mode).
  bool get isAvailable => SupabaseInit.isOnlineMode;

  void _requireOnline() {
    if (!SupabaseInit.isOnlineMode) throw Exception(_onlineError);
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    _requireOnline();
    final response = await _auth.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: kIsWeb ? null : _authRedirect,
      data: {'display_name': name},
    );
    final user = response.user;
    if (user == null) throw Exception('Registration failed: no user.');
    // Local admin fallback: the first user ever registered on this device
    // becomes the admin until a real isAdmin flag is set in Supabase.
    try {
      await AdminService.recordFirstUser(user.id);
    } catch (_) {
      // Best effort only.
    }
    // Best effort: create the profile row so the community can show it.
    try {
      await UserRepository.instance.saveUser(
        AppUser(id: user.id, name: name, email: email),
      );
    } catch (_) {
      // Profile row failure must not fail registration itself.
    }
  }

  Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    _requireOnline();
    await _auth.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signInWithGoogle() async {
    _requireOnline();
    // Supabase Auth's built-in OAuth (no google_sign_in package): opens
    // the browser for Google sign-in and returns to the app via deep link.
    // Returns false when the flow is cancelled / cannot start.
    final launched = await _auth.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : _authRedirect,
    );
    if (!launched) {
      throw Exception('Google sign-in cancelled.');
    }
    // The session arrives via onAuthStateChange after the redirect; if
    // the user object is already present (e.g. web), create the profile
    // row now. Otherwise the row is created on first profile load.
    final user = _auth.auth.currentUser;
    if (user != null) {
      try {
        final existing =
            await UserRepository.instance.getUser(user.id);
        if (existing == null) {
          final meta = user.userMetadata ?? {};
          await UserRepository.instance.saveUser(
            AppUser(
              id: user.id,
              name: (meta['display_name'] as String?) ??
                  (meta['full_name'] as String?) ??
                  (meta['name'] as String?) ??
                  'Student',
              email: user.email ?? '',
              photoUrl: meta['avatar_url'] as String?,
            ),
          );
        }
      } catch (_) {
        // Profile row failure must not fail sign-in itself.
      }
    }
  }

  Future<void> signOut() async {
    if (!SupabaseInit.isOnlineMode) return;
    await _auth.auth.signOut();
  }

  Future<void> sendEmailVerification() async {
    _requireOnline();
    final user = _auth.auth.currentUser;
    if (user == null) throw Exception('No user is signed in.');
    final email = user.email;
    if (email == null) throw Exception('No email on this account.');
    // Re-sends the Supabase signup confirmation email.
    await _auth.auth.resend(type: OtpType.signup, email: email);
  }

  /// Sends the password-reset email. The mail carries a 6-digit code
  /// (the dashboard template must include `{{ .Token }}`) AND the
  /// link as a fallback: on a phone the link opens the app and emits
  /// [AuthChangeEvent.passwordRecovery]; the code path verifies with
  /// [verifyRecoveryCode] instead. The deep link must be listed in
  /// the Supabase dashboard (Auth -> URL Configuration -> Redirect
  /// URLs).
  Future<void> sendPasswordResetEmail({required String email}) async {
    _requireOnline();
    await _auth.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : _authRedirect,
    );
  }

  /// Verifies the 6-digit signup code from the confirmation mail
  /// (the dashboard template must include `{{ .Token }}`). On success
  /// the session is set and the user is signed in.
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {
    _requireOnline();
    await _auth.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.signup,
    );
  }

  /// Re-sends the signup confirmation mail (new code).
  Future<void> resendSignupCode({required String email}) async {
    _requireOnline();
    await _auth.auth.resend(type: OtpType.signup, email: email);
  }

  /// Verifies the 6-digit recovery code from the reset mail and opens
  /// the set-new-password screen (via [recoveryPending]).
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    _requireOnline();
    await _auth.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    recoveryPending.value = true;
  }

  /// Sets the new password for the recovery session (after the user
  /// opened the reset link). The session stays valid afterwards, so
  /// the user lands signed in.
  Future<void> updatePassword({required String newPassword}) async {
    _requireOnline();
    await _auth.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Human-readable auth error: network/DNS failures become a plain
  /// "check your internet" message instead of the raw exception dump
  /// (which users cannot act on — e.g. the phone failing to resolve
  /// the Supabase host showed a full AuthRetryableFetchException /
  /// SocketException wall of text). Other known failures get a plain
  /// sentence too; anything else keeps its message minus the
  /// "Exception: " prefix.
  static String friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('Connection reset') ||
        text.contains('AuthRetryableFetchException') ||
        text.contains('ClientException')) {
      return 'No internet connection — check your Wi-Fi or mobile data and try again.';
    }
    if (text.contains('Invalid login credentials')) {
      return 'Wrong email or password. Try again.';
    }
    if (text.contains('User already registered')) {
      return 'This email already has an account — log in instead.';
    }
    if (text.contains('Password should be at least 6 characters')) {
      return 'Password must be at least 6 characters.';
    }
    if (text.contains('Email not confirmed')) {
      return 'Your email is not confirmed yet — check your inbox for the code.';
    }
    if (text.contains('otp_expired') || text.contains('Token has expired')) {
      return 'The code has expired — tap Resend for a new one.';
    }
    if (text.contains('over_email_send_rate_limit') ||
        text.contains('Email rate limit exceeded')) {
      return 'Too many emails sent — wait a few minutes and try again.';
    }
    return text.replaceFirst(RegExp(r'^Exception: '), '');
  }
}
