import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../security/secure_local_storage.dart';
import 'api_client.dart';

/// Email + 6-digit code login against the custom backend. No passwords,
/// no Google sign-in, no Supabase.
///
/// Flow: [sendLoginCode] (email) → the user types the code from the
/// mail → [verifyLoginCode] stores the 7-day JWT (Rafi's session rule)
/// and the user profile.
///
/// [restoreSession] reads a stored JWT at startup and validates it
/// with GET /api/auth/me. Best effort: with no network the stored
/// token is trusted and the app opens (the tracker is local-first);
/// a 401 clears the token and forces login.
///
/// There is NO anonymous / guest mode (Rafi, 2026-11-24): without a
/// valid JWT the app shows the login screen. Community authorship
/// always comes from the JWT user — never a local "Student" string —
/// and every backend feature requires the JWT.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  AppUser? _currentUser;

  /// The signed-in user, or null when logged out.
  AppUser? get currentUser => _currentUser;

  /// The signed-in uid, or null when logged out.
  String? get currentUid => _currentUser?.id;

  /// True while a JWT user is signed in. The app root listens to this
  /// to swap between the login screen and the tracker.
  final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);

  bool get isSignedIn => signedIn.value;

  /// Sends the 6-digit login code to [email]. Throws [ApiException]
  /// (e.g. EMAIL_DOMAIN_NOT_ALLOWED, TOO_SOON, EMAIL_NOT_CONFIGURED)
  /// on failure.
  Future<void> sendLoginCode({required String email}) async {
    await ApiClient.instance.post(
      '/api/auth/send-code',
      body: {'email': email.trim()},
    );
  }

  /// Verifies the 6-digit code, stores the JWT + profile, and flips
  /// [signedIn]. Returns the signed-in user. Throws [ApiException]
  /// (CODE_INVALID, CODE_EXPIRED, CODE_LOCKED, BANNED) on failure.
  Future<AppUser> verifyLoginCode({
    required String email,
    required String code,
  }) async {
    final res = await ApiClient.instance.post(
      '/api/auth/verify-code',
      body: {'email': email.trim(), 'code': code.trim()},
    );
    final token = res['token'] as String?;
    final userMap = res['user'] as Map?;
    if (token == null || token.isEmpty || userMap == null) {
      throw ApiException(
        'SERVER_ERROR',
        'Log-in failed — the server did not return a session. Try again.',
      );
    }
    await SecureLocalStorage.writeToken(token);
    await SecureLocalStorage.clearLegacySession();
    _currentUser = AppUser.fromMap(
      (userMap['id'] as String?) ?? '',
      userMap.cast<String, dynamic>(),
    );
    signedIn.value = true;
    return _currentUser!;
  }

  /// Startup restore: a stored JWT opens the app (optimistic — the
  /// tracker works offline). The token is validated with
  /// GET /api/auth/me in the background: a 401 clears it and flips
  /// [signedIn] to false; any other failure (offline, server down)
  /// keeps the stored token and lets the app open.
  Future<bool> restoreSession() async {
    final token = await SecureLocalStorage.readToken();
    if (token == null || token.isEmpty) return false;
    signedIn.value = true;
    try {
      final res = await ApiClient.instance.get('/api/auth/me', auth: true);
      final userMap = res['user'] as Map?;
      if (userMap != null) {
        _currentUser = AppUser.fromMap(
          (userMap['id'] as String?) ?? '',
          userMap.cast<String, dynamic>(),
        );
      }
    } on ApiException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        await signOut();
        return false;
      }
      // Offline / server down: keep the token, open the app.
    } catch (_) {
      // Same: the tracker is local-first, the session re-validates
      // on the next online call.
    }
    return signedIn.value;
  }

  /// Refreshes the cached profile from GET /api/auth/me. Returns the
  /// cached user when the call fails; null when not signed in.
  /// A 401 signs out (the session is dead) and rethrows.
  Future<AppUser?> refreshMe() async {
    if (!isSignedIn) return null;
    final res = await ApiClient.instance.get('/api/auth/me', auth: true);
    final userMap = res['user'] as Map?;
    if (userMap == null) return _currentUser;
    _currentUser = AppUser.fromMap(
      (userMap['id'] as String?) ?? '',
      userMap.cast<String, dynamic>(),
    );
    return _currentUser;
  }

  /// Signs out: clears the JWT + cached user and flips [signedIn].
  /// The app root shows the login screen again.
  Future<void> signOut() async {
    await SecureLocalStorage.clearToken();
    _currentUser = null;
    signedIn.value = false;
  }

  /// Human-readable auth error. [ApiException] codes map first (the
  /// custom backend's own codes); anything else falls through to the
  /// legacy substring rules (kept for the unit tests and for raw
  /// transport errors). Network/DNS failures become a plain "check
  /// your internet" message instead of the raw exception dump.
  static String friendlyError(Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 'CODE_INVALID':
          return 'Wrong code. Try again.';
        case 'CODE_EXPIRED':
          return 'The code has expired — tap Resend for a new one.';
        case 'CODE_LOCKED':
          return 'Too many wrong tries. Ask for a new code.';
        case 'TOO_SOON':
          return 'Wait a minute before asking for a new code.';
        case 'EMAIL_DOMAIN_NOT_ALLOWED':
          return 'Only Gmail, Hotmail, Outlook, and Yahoo emails are allowed.';
        case 'EMAIL_NOT_CONFIGURED':
          return 'Email sending is not set up on the server yet — ask the admin to set it.';
        case 'BANNED':
          return 'This account is banned.';
        case 'UNAUTHORIZED':
          return 'Please log in to continue.';
        case 'FORBIDDEN':
          return 'You are not allowed to do that.';
        case 'NOT_FOUND':
          return 'That was not found. Try again.';
      }
      return e.message;
    }
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
    if (text.contains('otp_expired') ||
        text.contains('Token has expired') ||
        text.contains('CODE_EXPIRED')) {
      return 'The code has expired — tap Resend for a new one.';
    }
    if (text.contains('over_email_send_rate_limit') ||
        text.contains('Email rate limit exceeded')) {
      return 'Too many emails sent — wait a few minutes and try again.';
    }
    return text.replaceFirst(RegExp(r'^Exception: '), '');
  }
}
