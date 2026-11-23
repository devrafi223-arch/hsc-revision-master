import 'dart:math' as math;

/// The per-day target system. Pure Dart — no Firebase, no I/O.
///
/// The user picks a custom target date; the remaining chapters are divided
/// evenly over the days left so the Today tab can show "today's plan".
class DailyPlan {
  /// Whole days from [today] to [targetDate], never negative. Dates are
  /// compared by calendar day (time of day ignored).
  static int daysLeft({
    required DateTime targetDate,
    required DateTime today,
  }) {
    final targetDay =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return math.max(0, targetDay.difference(todayDay).inDays);
  }

  /// Chapters to finish per day: ceil(remaining / max(daysLeft, 1)).
  /// Returns 0 when there is nothing left to do.
  static int chaptersPerDay({
    required int remainingChapters,
    required DateTime targetDate,
    required DateTime today,
  }) {
    if (remainingChapters <= 0) return 0;
    final days = math.max(daysLeft(targetDate: targetDate, today: today), 1);
    return (remainingChapters / days).ceil();
  }

  /// Today's plan: the first [perDay] ids from the remaining chapters,
  /// in the order given. Returns [] when [perDay] <= 0.
  static List<String> planForToday({
    required List<String> remainingChapterIds,
    required int perDay,
  }) {
    if (perDay <= 0) return [];
    return remainingChapterIds.take(perDay).toList();
  }
}
