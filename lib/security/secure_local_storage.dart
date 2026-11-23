import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the OS credential store (Android
/// Keystore / iOS Keychain / Windows Credential Vault / macOS Keychain)
/// instead of plain SharedPreferences, where the default
/// `SharedPreferencesLocalStorage` keeps the access + refresh tokens in
/// cleartext XML.
///
/// Fail-soft by design: every op catches platform errors (e.g. Linux
/// without libsecret) and degrades to "no persisted session" instead of
/// crashing auth — the user just signs in again.
///
/// On web this still works (flutter_secure_storage falls back to browser
/// storage there, which is only as safe as localStorage — documented
/// limit, same as the default).
class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage();

  static const _storage = FlutterSecureStorage();
  static const _key = 'sb-session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _storage.read(key: _key) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      final raw = await _storage.read(key: _key);
      final clean = storedSessionString(raw);
      if (raw != null && clean == null) {
        // A stored value that is not a JSON session is corrupt: drop
        // it so startup continues logged-out instead of crashing in
        // GoTrue's session recovery.
        await _storage.delete(key: _key);
      }
      return clean;
    } catch (_) {
      return null;
    }
  }

  /// The string supabase_flutter passes to GoTrue.setInitialSession /
  /// recoverSession must be the WHOLE stored JSON session — those
  /// methods json-decode it into a Session. Returning only the
  /// access_token field (a bare `eyJ...` JWT) made startup throw
  /// FormatException: Unexpected character (at character 1) on every
  /// launch with a persisted session (Windows crash, 2026-11-23).
  /// Anything that is not a JSON object is corrupt and yields null.
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

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: _key, value: persistSessionString);
    } catch (_) {}
  }
}
