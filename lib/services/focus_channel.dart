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
  const FocusPermissions({required this.accessibility, required this.overlay});

  final bool accessibility;
  final bool overlay;

  bool get allGranted => accessibility && overlay;
}

/// Bridge to the native Android Focus blocking service.
///
/// MethodChannel `com.afterclass.hsc/focus`, hosted by MainActivity.
/// Every call is guarded: on web / Windows / Linux (or if the native side
/// is missing) the methods return safe defaults instead of throwing, so
/// those builds keep compiling and passing tests. System-wide blocking
/// only exists on Android — everywhere else Focus Mode is in-app only.
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
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('startFocus', {
        'whitelist': whitelist,
        'endEpochMs': endEpochMs,
      });
    } catch (_) {
      // Native side missing: focus still works in-app.
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

  Future<FocusPermissions> checkPermissions() async {
    if (!isSupported) {
      return const FocusPermissions(accessibility: false, overlay: false);
    }
    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>(
              'checkPermissions');
      if (result == null) {
        return const FocusPermissions(accessibility: false, overlay: false);
      }
      return FocusPermissions(
        accessibility: result['accessibility'] == true,
        overlay: result['overlay'] == true,
      );
    } catch (_) {
      return const FocusPermissions(accessibility: false, overlay: false);
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
}
