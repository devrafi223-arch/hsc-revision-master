import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Device connectivity (wifi / mobile / none). Pure wrapper around
/// connectivity_plus — the single place screens and services ask
/// "are we online?".
///
/// (This replaces the connectivity half of the deleted SupabaseInit.)
class ConnectivityService {
  /// Emits true when the device has wifi / mobile / any connection,
  /// false when it has none.
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
