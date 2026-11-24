import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// JWT storage for the custom backend (replaces the old Supabase
/// session store). The token lives in the OS credential store
/// (Android Keystore / iOS Keychain / Windows Credential Vault),
/// never in cleartext SharedPreferences.
///
/// Fail-soft by design: every op catches platform errors (e.g. Linux
/// without libsecret) and degrades to "no token" instead of crashing —
/// the user just signs in again.
///
/// On web this still works (flutter_secure_storage falls back to
/// browser storage there, which is only as safe as localStorage —
/// documented limit, same as the old default).
class SecureLocalStorage {
  const SecureLocalStorage();

  static const _storage = FlutterSecureStorage();

  /// Key holding the custom-backend JWT (7-day session).
  static const _tokenKey = 'hsc-jwt-v1';

  /// Old Supabase session key — only ever deleted, never read for auth.
  static const _legacySessionKey = 'sb-session';

  static Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  static Future<void> clearToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
  }

  /// Drops a stale Supabase session left under the old key, if any.
  /// The old token is useless against the custom backend, and leaving
  /// it around would only confuse a future debug session.
  static Future<void> clearLegacySession() async {
    try {
      await _storage.delete(key: _legacySessionKey);
    } catch (_) {}
  }

  /// Legacy validator, kept for the unit test: a full JSON session
  /// passes through unchanged, while a bare JWT, garbage, or a
  /// non-object JSON value yields null.
  ///
  /// (The old Supabase session was a JSON object; returning only the
  /// access_token field — a bare `eyJ...` JWT — made GoTrue's session
  /// recovery throw FormatException on every launch with a persisted
  /// session. Windows crash, 2026-11-23.)
  @visibleForTesting
  static String? storedSessionString(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trimLeft();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
    } catch (_) {
      return null;
    }
    return raw;
  }
}
