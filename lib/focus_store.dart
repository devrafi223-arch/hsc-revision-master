import 'package:shared_preferences/shared_preferences.dart';

/// Focus Mode state, persisted in SharedPreferences.
///
/// Keys (all prefixed `focus-`, separate from the tracker keys):
/// - `focus-whitelist-v1`: the whitelisted package names (String list).
/// - `focus-end-v1`: session end time, epoch milliseconds.
/// - `focus-duration-v1`: chosen session length in minutes.
/// - `focus-chapter-v1`: the chapter being focused on (chapter id).
///
/// A session whose end time has passed is stale: [isActive] treats it as
/// inactive and [load]/[start] clear it, so blocking can never stay on
/// forever if the app is killed mid-focus.
class FocusStore {
  static const String whitelistKey = 'focus-whitelist-v1';
  static const String endKey = 'focus-end-v1';
  static const String durationKey = 'focus-duration-v1';
  static const String chapterKey = 'focus-chapter-v1';

  static const List<int> durationOptions = [15, 25, 45, 60];

  final Set<String> whitelist = {};
  DateTime? endTime;
  int durationMinutes = 25;
  String? focusChapterId;

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
    if (endTime != null && !isActive) {
      // Stale session (e.g. the app was killed mid-focus): clear it.
      await end();
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
  }

  bool get isActive =>
      endTime != null && endTime!.isAfter(DateTime.now());

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

  bool isWhitelisted(String packageName) => whitelist.contains(packageName);

  Future<void> toggleWhitelisted(String packageName) async {
    if (whitelist.contains(packageName)) {
      whitelist.remove(packageName);
    } else {
      whitelist.add(packageName);
    }
    await save();
  }

  Future<void> start({required int minutes, String? chapterId}) async {
    durationMinutes = minutes;
    focusChapterId = chapterId;
    endTime = DateTime.now().add(Duration(minutes: minutes));
    await save();
  }

  Future<void> end() async {
    endTime = null;
    focusChapterId = null;
    await save();
  }
}
