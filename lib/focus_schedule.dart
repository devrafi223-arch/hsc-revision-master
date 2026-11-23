import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Weekly focus schedule — Cold Turkey-style blocking times.
///
/// A week is 7 days x 96 blocks of 15 minutes each. A day is
/// [DateTime.weekday] (1 = Monday … 7 = Sunday); a block index is
/// 0..95, block *n* covers [n*15, n*15+15) minutes after midnight.
///
/// Stored as JSON in SharedPreferences (`focus-schedule-v1`):
/// `{"1":[32,33,...],"5":[...]}` — day string -> list of block indices.
/// The phone UI toggles whole hours (4 blocks at a time); the model
/// itself stays 15-minute blocks so the Android service and the
/// schedule grid agree exactly.
class FocusSchedule {
  static const String scheduleKey = 'focus-schedule-v1';
  static const int blocksPerDay = 96;
  static const int blockMinutes = 15;

  /// Day (1..7) -> set of blocked 15-minute block indices.
  final Map<int, Set<int>> blocks = {};

  static int blockIndexOf(DateTime time) =>
      (time.hour * 60 + time.minute) ~/ blockMinutes;

  bool isBlockedAt(DateTime time) {
    final dayBlocks = blocks[time.weekday];
    if (dayBlocks == null) return false;
    return dayBlocks.contains(blockIndexOf(time));
  }

  bool get isBlockedNow => isBlockedAt(DateTime.now());

  bool get hasAny => blocks.values.any((set) => set.isNotEmpty);

  /// End of the contiguous blocked run containing [time], or null if
  /// [time] is not inside a blocked run. Walks forward across midnight
  /// while the blocks continue (capped at 48h for safety).
  DateTime? activeBlockEnd(DateTime time) {
    if (!isBlockedAt(time)) return null;
    var cursor = time;
    var end = _blockEnd(cursor);
    while (isBlockedAt(cursor.add(const Duration(minutes: blockMinutes)))) {
      cursor = cursor.add(const Duration(minutes: blockMinutes));
      end = _blockEnd(cursor);
      if (cursor.difference(time).inHours >= 48) break;
    }
    return end;
  }

  DateTime _blockEnd(DateTime time) {
    final index = blockIndexOf(time);
    return DateTime(time.year, time.month, time.day)
        .add(Duration(minutes: (index + 1) * blockMinutes));
  }

  /// All four 15-minute blocks of [hour] on [day] (0..23).
  bool isHourBlocked(int day, int hour) {
    final dayBlocks = blocks[day];
    if (dayBlocks == null) return false;
    for (var i = 0; i < 4; i++) {
      if (!dayBlocks.contains(hour * 4 + i)) return false;
    }
    return true;
  }

  bool isHourPartiallyBlocked(int day, int hour) {
    final dayBlocks = blocks[day];
    if (dayBlocks == null) return false;
    for (var i = 0; i < 4; i++) {
      if (dayBlocks.contains(hour * 4 + i)) return true;
    }
    return false;
  }

  /// Toggle a whole hour on [day]: if any of its blocks is set, clear
  /// all four; otherwise set all four.
  void toggleHour(int day, int hour) {
    final dayBlocks = blocks.putIfAbsent(day, () => <int>{});
    if (isHourPartiallyBlocked(day, hour)) {
      for (var i = 0; i < 4; i++) {
        dayBlocks.remove(hour * 4 + i);
      }
    } else {
      for (var i = 0; i < 4; i++) {
        dayBlocks.add(hour * 4 + i);
      }
    }
    if (dayBlocks.isEmpty) blocks.remove(day);
  }

  /// Set an hour range on [day] (end hour exclusive), e.g. 8..13.
  void setHours(int day, int startHour, int endHour, bool value) {
    final dayBlocks = blocks.putIfAbsent(day, () => <int>{});
    for (var hour = startHour; hour < endHour; hour++) {
      for (var i = 0; i < 4; i++) {
        if (value) {
          dayBlocks.add(hour * 4 + i);
        } else {
          dayBlocks.remove(hour * 4 + i);
        }
      }
    }
    if (dayBlocks.isEmpty) blocks.remove(day);
  }

  void clearDay(int day) => blocks.remove(day);

  void clearAll() => blocks.clear();

  String toJsonString() {
    final map = <String, List<int>>{};
    for (final entry in blocks.entries) {
      if (entry.value.isNotEmpty) {
        map[entry.key.toString()] = entry.value.toList()..sort();
      }
    }
    return jsonEncode(map);
  }

  static FocusSchedule fromJsonString(String? json) {
    final schedule = FocusSchedule();
    if (json == null || json.isEmpty) return schedule;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      for (final entry in decoded.entries) {
        final day = int.tryParse(entry.key);
        if (day == null || day < 1 || day > 7) continue;
        final list = (entry.value as List)
            .map((e) => e is int ? e : int.tryParse(e.toString()))
            .whereType<int>()
            .where((b) => b >= 0 && b < blocksPerDay);
        schedule.blocks[day] = list.toSet();
      }
    } catch (_) {
      // Corrupt schedule: start empty rather than crash.
    }
    return schedule;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = fromJsonString(prefs.getString(scheduleKey));
    blocks
      ..clear()
      ..addAll(loaded.blocks);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scheduleKey, toJsonString());
  }
}
