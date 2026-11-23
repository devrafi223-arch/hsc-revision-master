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
}
