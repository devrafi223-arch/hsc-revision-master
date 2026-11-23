import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Boots Firebase (when a real config exists) and tracks connectivity.
///
/// LOCAL-ONLY mode: while [DefaultFirebaseOptions] still holds the
/// placeholder values, [initialize] returns false, [isOnlineMode] stays
/// false, and nothing throws — the app keeps working fully offline.
class FirebaseInit {
  /// True only when Firebase was initialised with a real project config.
  static bool isOnlineMode = false;

  /// Initialises Firebase. Never throws and never rethrows.
  /// Returns true when online mode is available, false otherwise.
  static Future<bool> initialize() async {
    final options = DefaultFirebaseOptions.currentPlatform;
    // Placeholder config → stay in local-only mode, don't even try.
    if (options.apiKey.startsWith('TODO') ||
        options.projectId.startsWith('TODO') ||
        options.appId.startsWith('TODO')) {
      isOnlineMode = false;
      return false;
    }
    try {
      await Firebase.initializeApp(options: options);
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
