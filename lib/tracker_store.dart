import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'data/syllabus.dart';

/// Persistence for the tracker. Progress lives under the same key the
/// web versions use: `hsc-revision-master-v2`.
class TrackerStore {
  static const String checksKey = 'hsc-revision-master-v2';
  static const String targetDateKey = 'hsc-target-date-v2';

  final Map<String, bool> checks = {};
  DateTime? targetDate;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(checksKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        checks
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, v == true)));
      } catch (_) {
        checks.clear();
      }
    }
    final target = prefs.getString(targetDateKey);
    if (target != null && target.isNotEmpty) {
      targetDate = DateTime.tryParse(target);
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(checksKey, jsonEncode(checks));
    if (targetDate != null) {
      await prefs.setString(targetDateKey, targetDate!.toIso8601String());
    }
  }

  bool isDone(String chapterId, String stageId) =>
      checks['${chapterId}_$stageId'] == true;

  void toggle(String chapterId, String stageId) {
    final key = '${chapterId}_$stageId';
    if (checks[key] == true) {
      checks.remove(key);
    } else {
      checks[key] = true;
    }
  }

  int get doneCount => checks.values.where((v) => v).length;

  int doneForChapter(String chapterId) => revisionStages
      .where((s) => isDone(chapterId, s.id))
      .length;

  /// Subject with the lowest completion percentage (ties: first in list).
  Subject weakestSubject(List<ChapterRef> refs) {
    Subject? worst;
    double worstPct = 2;
    for (final subject in syllabusData) {
      final chapters =
          refs.where((r) => r.subject.id == subject.id).toList();
      final total = chapters.length * revisionStages.length;
      if (total == 0) continue;
      final done = chapters.fold<int>(
        0,
        (n, r) => n + doneForChapter(r.chapter.id),
      );
      final pct = done / total;
      if (pct < worstPct) {
        worstPct = pct;
        worst = subject;
      }
    }
    return worst ?? syllabusData.first;
  }

  List<ChapterRef> pendingChapters(List<ChapterRef> refs) => refs
      .where((r) => doneForChapter(r.chapter.id) < revisionStages.length)
      .toList();

  String exportJson() => jsonEncode({
        'app': 'hsc-revision-master',
        'version': 2,
        'checks': checks,
        'targetDate': targetDate?.toIso8601String(),
      });

  /// Returns true when the pasted JSON was a valid backup of this app.
  bool importJson(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final incoming = decoded['checks'];
      if (incoming is! Map) return false;
      checks
        ..clear()
        ..addAll(
          incoming.map((k, v) => MapEntry(k.toString(), v == true)),
        );
      final target = decoded['targetDate'];
      if (target is String) targetDate = DateTime.tryParse(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  String whatsAppSummary() {
    final buffer = StringBuffer()
      ..writeln('📚 HSC Science Revision Master')
      ..writeln('Progress: $doneCount / $totalMilestones '
          '(${(doneCount * 100 / totalMilestones).round()}%)');
    for (final subject in syllabusData) {
      final refs = allChapterRefs
          .where((r) => r.subject.id == subject.id)
          .toList();
      final total = refs.length * revisionStages.length;
      final done = refs.fold<int>(
        0,
        (n, r) => n + doneForChapter(r.chapter.id),
      );
      buffer.writeln(
        '• ${subject.nameEn}: $done/$total (${(done * 100 / total).round()}%)',
      );
    }
    return buffer.toString();
  }
}
