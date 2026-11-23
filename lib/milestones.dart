/// Milestone names and badge names. Pure Dart — no Firebase, no I/O.
///
/// Every subject + chapter gets a DIFFERENT milestone: the name is
/// deterministic and unique per subject + chapter, built from the subject's
/// title word, the subject name, the chapter number and the chapter title.
class Milestones {
  /// Subject-specific title word. Keys are the exact subject names from
  /// lib/data/syllabus.dart (nameEn). "Higher Mathematics" is the syllabus
  /// spelling; "Higher Math" is accepted too.
  static const Map<String, String> _titleWords = {
    'Physics': 'Physics Pioneer',
    'Chemistry': 'Chemistry Catalyst',
    'Higher Math': 'Math Master',
    'Higher Mathematics': 'Math Master',
    'Biology': 'Bio Explorer',
    'Bangla': 'Bangla Bard',
    'English': 'English Envoy',
    'ICT': 'ICT Innovator',
  };

  /// e.g. "Physics Pioneer — Physics — Chapter 1: ভৌত জগৎ ও পরিমাপ".
  /// [chapterIndex] is 0-based within the subject.
  static String nameFor(
    String subject,
    String chapterTitle,
    int chapterIndex,
  ) {
    final titleWord = _titleWords[subject] ?? '$subject Star';
    return '$titleWord — $subject — Chapter ${chapterIndex + 1}: '
        '$chapterTitle';
  }

  /// Badge names earned so far. Thresholds (each badge appears once its
  /// threshold is reached):
  /// first chapter, 10 / 50 / 100 chapters, 7-day / 30-day streak.
  static List<String> badgeNamesFor({
    required int streak,
    required int totalChapters,
  }) {
    final badges = <String>[];
    if (totalChapters >= 1) badges.add('First chapter');
    if (totalChapters >= 10) badges.add('10 chapters');
    if (totalChapters >= 50) badges.add('50 chapters');
    if (totalChapters >= 100) badges.add('100 chapters');
    if (streak >= 7) badges.add('7-day streak');
    if (streak >= 30) badges.add('30-day streak');
    return badges;
  }
}
