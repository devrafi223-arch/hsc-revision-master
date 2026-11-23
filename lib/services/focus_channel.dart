import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One launchable Android app, as reported by the native side.
class InstalledApp {
  const InstalledApp({required this.label, required this.packageName});

  final String label;
  final String packageName;
}

/// Permission state for system-wide blocking on Android.
class FocusPermissions {
  const FocusPermissions({
    required this.accessibility,
    required this.overlay,
    required this.usage,
  });

  final bool accessibility;
  final bool overlay;

  /// Usage access (PACKAGE_USAGE_STATS) — only needed for daily caps
  /// and per-app usage stats, not for basic focus blocking.
  final bool usage;

  bool get allGranted => accessibility && overlay;
}

/// Bridge to the native Android Focus blocking service.
///
/// MethodChannel `com.afterclass.hsc/focus`, hosted by MainActivity.
/// Every call is guarded: on web / Windows / Linux (or if the native side
/// is missing) the methods return safe defaults instead of throwing, so
/// those builds keep compiling and passing tests. System-wide blocking
/// only exists on Android — everywhere else Focus Mode is in-app only.
///
/// The native service keeps its own copy of the blocking rules in its
/// `focus_prefs` file (written through [startFocus] / [syncBlocking]):
/// the whitelist, the manual session end time, the locked flag, the
/// weekly schedule JSON, the daily caps JSON and the schedule
/// dismiss-until time. The service evaluates the schedule and the caps
/// on every foreground-app event, so blocking keeps working even if
/// the app itself is killed.
class FocusChannel {
  static const MethodChannel _channel =
      MethodChannel('com.afterclass.hsc/focus');

  /// True only on real Android (never on web/desktop, never in tests).
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<List<InstalledApp>> getInstalledApps() async {
    if (!isSupported) return [];
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (result == null) return [];
      return result
          .whereType<Map>()
          .map((m) => InstalledApp(
                label: m['label']?.toString() ?? '',
                packageName: m['packageName']?.toString() ?? '',
              ))
          .where((a) => a.packageName.isNotEmpty && a.label.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> startFocus({
    required List<String> whitelist,
    required int endEpochMs,
    bool locked = false,
    String scheduleJson = '{}',
    String capsJson = '{}',
    int dismissedUntilMs = 0,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('startFocus', {
        'whitelist': whitelist,
        'endEpochMs': endEpochMs,
        'locked': locked,
        'schedule': scheduleJson,
        'caps': capsJson,
        'dismissedUntilMs': dismissedUntilMs,
      });
    } catch (_) {
      // Native side missing: focus still works in-app.
    }
  }

  /// Push the schedule / locked / caps rules to the native service
  /// without starting or stopping a session — so the service can
  /// enforce scheduled blocks and daily caps on its own.
  Future<void> syncBlocking({
    required String scheduleJson,
    required bool locked,
    required String capsJson,
    int dismissedUntilMs = 0,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('syncBlocking', {
        'schedule': scheduleJson,
        'locked': locked,
        'caps': capsJson,
        'dismissedUntilMs': dismissedUntilMs,
      });
    } catch (_) {
      // Native side missing: nothing to sync.
    }
  }

  Future<void> stopFocus() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('stopFocus');
    } catch (_) {
      // Nothing to stop.
    }
  }

  Future<bool> isFocusActive() async {
    if (!isSupported) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isFocusActive');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Today's foreground minutes per package (UsageStatsManager).
  /// Empty on non-Android or when usage access is not granted.
  Future<Map<String, int>> getDailyUsage() async {
    if (!isSupported) return {};
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getDailyUsage');
      if (result == null) return {};
      final out = <String, int>{};
      for (final entry in result.entries) {
        final minutes = entry.value is int
            ? entry.value as int
            : int.tryParse('${entry.value}');
        if (minutes != null && minutes > 0) {
          out[entry.key.toString()] = minutes;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<FocusPermissions> checkPermissions() async {
    if (!isSupported) {
      return const FocusPermissions(
          accessibility: false, overlay: false, usage: false);
    }
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'checkPermissions');
      if (result == null) {
        return const FocusPermissions(
            accessibility: false, overlay: false, usage: false);
      }
      return FocusPermissions(
        accessibility: result['accessibility'] == true,
        overlay: result['overlay'] == true,
        usage: result['usage'] == true,
      );
    } catch (_) {
      return const FocusPermissions(
          accessibility: false, overlay: false, usage: false);
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } catch (_) {
      // Settings could not be opened; the user can open them manually.
    }
  }

  Future<void> openOverlaySettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } catch (_) {
      // Settings could not be opened; the user can open them manually.
    }
  }

  Future<void> openUsageSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openUsageSettings');
    } catch (_) {
      // Settings could not be opened; the user can open them manually.
    }
  }

  /// Opens this app's App info screen — needed for the
  /// "Allow restricted settings" step on Android 13+ sideloaded APKs.
  Future<void> openAppInfo() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openAppInfo');
    } catch (_) {
      // Settings could not be opened; the user can open them manually.
    }
  }
}
