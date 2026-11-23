import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../security/pinning.dart';
import '../security/secure_local_storage.dart';
import '../supabase_config.dart';

/// Boots Supabase (when a real config exists) and tracks connectivity.
///
/// LOCAL-ONLY mode: while [SupabaseConfig] still holds the placeholder
/// values, [initialize] returns false, [isOnlineMode] stays false, and
/// nothing throws — the app keeps working fully offline.
///
/// [isOnlineMode] is the flag every service checks (same name the old
/// Firebase init exposed, so callers did not need to change).
/// [isOnlineCapable] is the same value under the name the migration spec
/// uses; [isConfigured] is true only once real (non-TODO) values are in
/// [SupabaseConfig].
class SupabaseInit {
  /// True only when Supabase was initialised with a real project config.
  static bool isOnlineMode = false;

  /// Same as [isOnlineMode]: true only when online features can run.
  static bool get isOnlineCapable => isOnlineMode;

  /// True when [SupabaseConfig] holds real (non-placeholder) values.
  static bool get isConfigured =>
      !SupabaseConfig.url.startsWith('TODO') &&
      !SupabaseConfig.anonKey.startsWith('TODO');

  /// The Supabase client. Only touch it while [isOnlineMode] is true —
  /// before [initialize] runs, `Supabase.instance` throws.
  static SupabaseClient get client => Supabase.instance.client;

  /// Initialises Supabase. Never throws and never rethrows.
  /// Returns true when online mode is available, false otherwise.
  static Future<bool> initialize() async {
    // Placeholder config → stay in local-only mode, don't even try.
    if (!isConfigured) {
      isOnlineMode = false;
      return false;
    }
    try {
      // STANDARD SECURITY (v3): fail-closed TLS CA pinning + encrypted
      // session storage. installPinnedHttpOverrides() is a no-op on web
      // (dart:io does not exist there; the browser owns TLS).
      installPinnedHttpOverrides();
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // `anonKey` is deprecated in supabase_flutter 2.18 in favour of
        // `publishableKey`; same value (the anon key from the dashboard).
        publishableKey: SupabaseConfig.anonKey,
        // Pinned http client: every REST / Auth / Storage call only trusts
        // the roots in lib/security/pinned_certs.dart. Null on web.
        httpClient: buildPinnedHttpClient(),
        // Session tokens live in the OS keychain/keystore, never in
        // cleartext SharedPreferences.
        authOptions: const FlutterAuthClientOptions(
          localStorage: SecureLocalStorage(),
        ),
      );
      isOnlineMode = true;
      return true;
    } catch (_) {
      // No network, bad config, unsupported platform — local-only mode.
      isOnlineMode = false;
      return false;
    }
  }

  /// Emits true when the device has wifi/mobile/any connection, false
  /// when it has none. Backed by connectivity_plus.
  static Stream<bool> get connectivityStream =>
      Connectivity().onConnectivityChanged.map(
            (results) => results.any(
              (r) => r != ConnectivityResult.none,
            ),
          );

  /// One-shot connectivity check (best effort, false on any error).
  static Future<bool> get isConnected async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }
}
