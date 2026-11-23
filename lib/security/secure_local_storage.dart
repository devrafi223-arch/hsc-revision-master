import 'dart:convert';

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
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return json['access_token'] as String?;
    } catch (_) {
      return null;
    }
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
