// HSC Revision Master v3 — pure-logic tests (no Firebase, no I/O).
//
// Covers: Milestones naming + badges, DailyPlan per-day math,
// OfflineQueue, and the Milestone model round-trip.
// (Community is gone: the PollData / Moderation / CommunityMessage
// sections were deleted with it.)

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/data/syllabus.dart';
import 'package:hsc_revision_master/milestones.dart';
import 'package:hsc_revision_master/models/milestone.dart';
import 'package:hsc_revision_master/services/offline_queue.dart';
import 'package:hsc_revision_master/target_plan.dart';

void main() {
  // ------------------------------------------------------------------
  // 1. Milestone naming
  // ------------------------------------------------------------------
  group('Milestones.nameFor', () {
    test('returns a DIFFERENT name for every one of the 151 chapters',
        () {
      expect(totalChapters, 151);
      final names = <String>{};
      // Chapter index is 0-based *within the subject*, so track a
      // per-subject counter while walking the syllabus.
      final perSubjectIndex = <String, int>{};
      for (final ref in allChapterRefs) {
        final index = perSubjectIndex[ref.subject.nameEn] ?? 0;
        perSubjectIndex[ref.subject.nameEn] = index + 1;
        names.add(
          Milestones.nameFor(
            ref.subject.nameEn,
            ref.chapter.title,
            index,
          ),
        );
      }
      expect(names.length, 151,
          reason: 'one unique milestone name per chapter');
    });

    test('same chapter called twice returns the same name', () {
      final first = Milestones.nameFor('Physics', 'ভেক্টর', 1);
      final second = Milestones.nameFor('Physics', 'ভেক্টর', 1);
      expect(first, second);
    });

    test('each name contains its subject', () {
      for (final ref in allChapterRefs) {
        final index = ref.chapter.no - 1;
        final name = Milestones.nameFor(
          ref.subject.nameEn,
          ref.chapter.title,
          index,
        );
        expect(name, contains(ref.subject.nameEn),
            reason: 'name for ${ref.chapter.id} should name its subject');
      }
    });

    test('Physics chapter 1 name starts with "Physics Pioneer"', () {
      final name = Milestones.nameFor('Physics', 'ভৌত জগৎ ও পরিমাপ', 0);
      expect(name, startsWith('Physics Pioneer'));
    });
  });

  // ------------------------------------------------------------------
  // 2. Badges
  // ------------------------------------------------------------------
  group('Milestones.badgeNamesFor', () {
    test('7-day streak earns a 7-day streak badge', () {
      final badges =
          Milestones.badgeNamesFor(streak: 7, totalChapters: 0);
      expect(badges, contains('7-day streak'));
    });

    test('50 chapters earns a 50-chapter badge', () {
      final badges =
          Milestones.badgeNamesFor(streak: 0, totalChapters: 50);
      expect(badges, contains('50 chapters'));
    });

    test('no streak and no chapters earns no badges', () {
      expect(
        Milestones.badgeNamesFor(streak: 0, totalChapters: 0),
        isEmpty,
      );
    });
  });

  // ------------------------------------------------------------------
  // 3. Per-day target math (DailyPlan)
  // ------------------------------------------------------------------
  group('DailyPlan', () {
    final today = DateTime(2026, 11, 23);
    final in10Days = DateTime(2026, 12, 3);

    test('30 remaining, target 10 days away = 3 per day', () {
      expect(
        DailyPlan.chaptersPerDay(
          remainingChapters: 30,
          targetDate: in10Days,
          today: today,
        ),
        3,
      );
    });

    test('31 remaining, target 10 days away = 4 per day (ceil)', () {
      expect(
        DailyPlan.chaptersPerDay(
          remainingChapters: 31,
          targetDate: in10Days,
          today: today,
        ),
        4,
      );
    });

    test('0 remaining = 0 per day', () {
      expect(
        DailyPlan.chaptersPerDay(
          remainingChapters: 0,
          targetDate: in10Days,
          today: today,
        ),
        0,
      );
    });

    test('past target date puts all remaining chapters in one day', () {
      final past = DateTime(2026, 11, 1);
      expect(
        DailyPlan.daysLeft(targetDate: past, today: today),
        0,
        reason: 'daysLeft clamps to >= 0',
      );
      expect(
        DailyPlan.chaptersPerDay(
          remainingChapters: 25,
          targetDate: past,
          today: today,
        ),
        25,
      );
    });

    test('daysLeft returns 0 for a past date and the right count for a '
        'future date', () {
      expect(
        DailyPlan.daysLeft(
          targetDate: DateTime(2026, 11, 1),
          today: today,
        ),
        0,
      );
      expect(
        DailyPlan.daysLeft(targetDate: in10Days, today: today),
        10,
      );
      expect(
        DailyPlan.daysLeft(targetDate: today, today: today),
        0,
      );
    });

    test('planForToday returns exactly perDay ids, and fewer when fewer '
        'remain', () {
      final remaining = ['c1', 'c2', 'c3', 'c4', 'c5'];
      expect(
        DailyPlan.planForToday(
          remainingChapterIds: remaining,
          perDay: 3,
        ),
        ['c1', 'c2', 'c3'],
      );
      expect(
        DailyPlan.planForToday(
          remainingChapterIds: ['c1', 'c2'],
          perDay: 5,
        ),
        ['c1', 'c2'],
      );
      expect(
        DailyPlan.planForToday(
          remainingChapterIds: remaining,
          perDay: 0,
        ),
        isEmpty,
      );
    });
  });

  // ------------------------------------------------------------------
  // 4. Offline queue
  // ------------------------------------------------------------------
  group('OfflineQueue', () {
    OfflineQueue buildQueue() {
      final queue = OfflineQueue();
      queue.enqueue({'type': 'note', 'text': 'first'});
      queue.enqueue({'type': 'note', 'text': 'second'});
      queue.enqueue({'type': 'note', 'text': 'third'});
      return queue;
    }

    test('enqueue 3 ops: length is 3 and pending preserves order', () {
      final queue = buildQueue();
      expect(queue.length, 3);
      expect(queue.isEmpty, isFalse);
      expect(queue.pending[0]['text'], 'first');
      expect(queue.pending[1]['text'], 'second');
      expect(queue.pending[2]['text'], 'third');
    });

    test('toJson/fromJson round-trip preserves all ops', () {
      final queue = buildQueue();
      final decoded = jsonDecode(queue.toJson()) as List<dynamic>;
      final restored = OfflineQueue.fromJson(decoded);
      expect(restored.length, 3);
      expect(restored.pending[0]['type'], 'note');
      expect(restored.pending[0]['text'], 'first');
      expect(restored.pending[1]['text'], 'second');
      expect(restored.pending[2]['type'], 'note');
      // The string form parses back identically too.
      final restored2 = OfflineQueue.fromJsonString(queue.toJson());
      expect(restored2.length, 3);
      expect(restored2.pending[2]['text'], 'third');
    });

    test('removeAt removes the right op and clear empties the queue',
        () {
      final queue = buildQueue();
      queue.removeAt(1);
      expect(queue.length, 2);
      expect(queue.pending[0]['text'], 'first');
      expect(queue.pending[1]['text'], 'third');
      queue.clear();
      expect(queue.length, 0);
      expect(queue.isEmpty, isTrue);
      expect(queue.pending, isEmpty);
    });
  });

  // ------------------------------------------------------------------
  // 5. Milestone model round-trip
  // ------------------------------------------------------------------
  test('Milestone toMap/fromMap round-trip preserves id, name, subject, '
      'and chapterTitle', () {
    final original = Milestone(
      id: 'ms-phy1_1',
      name: Milestones.nameFor('Physics', 'ভৌত জগৎ ও পরিমাপ', 0),
      subject: 'Physics',
      chapterTitle: 'ভৌত জগৎ ও পরিমাপ',
      earnedAt: DateTime.utc(2026, 11, 23, 12, 0),
    );
    // fromMap takes the doc id as a separate argument (toMap stores
    // name/subject/chapterTitle/earnedAt; the id is the document id).
    final restored = Milestone.fromMap(original.id, original.toMap());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.subject, original.subject);
    expect(restored.chapterTitle, original.chapterTitle);
    expect(
      restored.earnedAt.millisecondsSinceEpoch,
      original.earnedAt.millisecondsSinceEpoch,
    );
  });
}
