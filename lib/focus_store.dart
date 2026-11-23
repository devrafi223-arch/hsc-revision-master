import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Focus Mode state, persisted in SharedPreferences.
///
/// Keys (all prefixed `focus-`, separate from the tracker keys):
/// - `focus-whitelist-v1`: whitelisted Android package names (String list).
/// - `focus-end-v1`: session end time, epoch milliseconds.
/// - `focus-duration-v1`: chosen session length in minutes.
/// - `focus-chapter-v1`: the chapter being focused on (chapter id).
/// - `focus-locked-v1`: locked sessions can't be ended early.
/// - `focus-caps-v1`: daily caps, JSON `{packageName: minutes}`.
/// - `focus-desktop-whitelist-v1`: PC exe names that stay usable
///   (lowercase basenames, e.g. `notepad.exe`).
/// - `focus-auto-v1`: the current session was started by the schedule.
/// - `focus-schedule-dismissed-v1`: epoch ms until which a schedule
///   block must not auto-restart (set when the user ends a scheduled
///   session early).
///
/// A session whose end time has passed is stale: [isActive] treats it as
/// inactive and [load]/[start] clear it, so blocking can never stay on
/// forever if the app is killed mid-focus. Locked only ever blocks an
/// *early* end — once the end time passes the session is over.
class FocusStore {
  static const String whitelistKey = 'focus-whitelist-v1';
  static const String endKey = 'focus-end-v1';
  static const String durationKey = 'focus-duration-v1';
  static const String chapterKey = 'focus-chapter-v1';
  static const String lockedKey = 'focus-locked-v1';
  static const String capsKey = 'focus-caps-v1';
  static const String desktopWhitelistKey = 'focus-desktop-whitelist-v1';
  static const String autoKey = 'focus-auto-v1';
  static const String scheduleDismissedKey = 'focus-schedule-dismissed-v1';

  static const List<int> durationOptions = [15, 25, 45, 60];

  final Set<String> whitelist = {};
  DateTime? endTime;
  int durationMinutes = 25;
  String? focusChapterId;

  /// When true, the running session cannot be ended early — the End
  /// button is disabled (and the Android block overlay hides its End
  /// button) until the timer finishes.
  bool locked = false;

  /// Daily caps: package name -> allowed foreground minutes per day.
  /// When a cap is reached the Android service blocks that app for the
  /// rest of the day, even outside a focus session (HALT model). A cap
  /// beats the whitelist — a limit is a limit.
  final Map<String, int> caps = {};

  /// PC exe basenames (lowercase) that stay usable during PC focus.
  /// The revision app itself is always allowed.
  final Set<String> desktopWhitelist = {};

  /// True when the current session was started by the weekly schedule.
  bool autoStarted = false;

  /// Until when a schedule block must not auto-restart.
  DateTime? scheduleDismissedUntil;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    whitelist
      ..clear()
      ..addAll(prefs.getStringList(whitelistKey) ?? []);
    durationMinutes = prefs.getInt(durationKey) ?? 25;
    if (!durationOptions.contains(durationMinutes)) durationMinutes = 25;
    final endMs = prefs.getInt(endKey);
    endTime = endMs == null ? null : DateTime.fromMillisecondsSinceEpoch(endMs);
    focusChapterId = prefs.getString(chapterKey);
    locked = prefs.getBool(lockedKey) ?? false;
    caps
      ..clear()
      ..addAll(_decodeCaps(prefs.getString(capsKey)));
    desktopWhitelist
      ..clear()
      ..addAll(prefs.getStringList(desktopWhitelistKey) ?? []);
    autoStarted = prefs.getBool(autoKey) ?? false;
    final dismissedMs = prefs.getInt(scheduleDismissedKey);
    scheduleDismissedUntil = dismissedMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(dismissedMs);
    if (endTime != null && !isActive) {
      // Stale session (e.g. the app was killed mid-focus): clear it.
      await end();
    }
    if (scheduleDismissedUntil != null &&
        scheduleDismissedUntil!.isBefore(DateTime.now())) {
      scheduleDismissedUntil = null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(whitelistKey, whitelist.toList());
    await prefs.setInt(durationKey, durationMinutes);
    if (endTime != null) {
      await prefs.setInt(endKey, endTime!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(endKey);
    }
    if (focusChapterId != null) {
      await prefs.setString(chapterKey, focusChapterId!);
    } else {
      await prefs.remove(chapterKey);
    }
    await prefs.setBool(lockedKey, locked);
    await prefs.setString(capsKey, jsonEncode(caps));
    await prefs.setStringList(
        desktopWhitelistKey, desktopWhitelist.toList());
    await prefs.setBool(autoKey, autoStarted);
    if (scheduleDismissedUntil != null) {
      await prefs.setInt(
          scheduleDismissedKey, scheduleDismissedUntil!.millisecondsSinceEpoch);
    } else {
      await prefs.remove(scheduleDismissedKey);
    }
  }

  static Map<String, int> _decodeCaps(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final out = <String, int>{};
      for (final entry in decoded.entries) {
        final value =
            entry.value is int ? entry.value as int : int.tryParse('${entry.value}');
        if (value != null && value > 0) out[entry.key] = value;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  String get capsJson => jsonEncode(caps);

  bool get isActive =>
      endTime != null && endTime!.isAfter(DateTime.now());

  /// Locked sessions can only end when the timer has finished.
  bool get canEnd => !locked || !isActive;

  /// True while the schedule must not auto-restart a session.
  bool get scheduleDismissedNow =>
      scheduleDismissedUntil != null &&
      scheduleDismissedUntil!.isAfter(DateTime.now());

  Duration get remaining {
    if (endTime == null) return Duration.zero;
    final left = endTime!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get remainingLabel {
    final total = remaining.inSeconds;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// "Locked — ends at 14:35, cannot be stopped early."
  String get lockedLabel {
    if (endTime == null) return '';
    final hour = endTime!.hour.toString().padLeft(2, '0');
    final minute = endTime!.minute.toString().padLeft(2, '0');
    return 'Locked — ends at $hour:$minute, cannot be stopped early.';
  }

  bool isWhitelisted(String packageName) => whitelist.contains(packageName);

  Future<void> toggleWhitelisted(String packageName) async {
    if (whitelist.contains(packageName)) {
      whitelist.remove(packageName);
    } else {
      whitelist.add(packageName);
    }
    await save();
  }

  bool isDesktopWhitelisted(String exeName) =>
      desktopWhitelist.contains(exeName.toLowerCase());

  Future<void> toggleDesktopWhitelisted(String exeName) async {
    final name = exeName.trim().toLowerCase();
    if (name.isEmpty) return;
    if (desktopWhitelist.contains(name)) {
      desktopWhitelist.remove(name);
    } else {
      desktopWhitelist.add(name);
    }
    await save();
  }

  Future<void> setCap(String packageName, int minutes) async {
    if (minutes <= 0) {
      caps.remove(packageName);
    } else {
      caps[packageName] = minutes;
    }
    await save();
  }

  Future<void> removeCap(String packageName) async {
    caps.remove(packageName);
    await save();
  }

  Future<void> setLocked(bool value) async {
    locked = value;
    await save();
  }

  Future<void> start({required int minutes, String? chapterId}) async {
    await startUntil(
      DateTime.now().add(Duration(minutes: minutes)),
      minutes: minutes,
      chapterId: chapterId,
    );
  }

  /// Start a session that ends at an exact time (used by the schedule
  /// auto-start, where the end is the end of the blocked run).
  Future<void> startUntil(
    DateTime end, {
    int? minutes,
    String? chapterId,
    bool auto = false,
  }) async {
    if (minutes != null) durationMinutes = minutes;
    focusChapterId = chapterId;
    endTime = end;
    autoStarted = auto;
    await save();
  }

  /// User-initiated end. Returns false when a locked session is still
  /// running — it cannot be stopped early. Use [end] for the internal
  /// paths (timer expiry, stale cleanup) that must always clear.
  Future<bool> tryEnd() async {
    if (!canEnd) return false;
    await end();
    return true;
  }

  Future<void> end() async {
    endTime = null;
    focusChapterId = null;
    autoStarted = false;
    await save();
  }

  /// Stop the schedule from auto-restarting until [until] (used when
  /// the user ends a scheduled session early).
  Future<void> dismissScheduleUntil(DateTime until) async {
    scheduleDismissedUntil = until;
    await save();
  }
}
