// HSC Revision Master v3 — pure-logic tests (no Firebase, no I/O).
//
// Covers: Milestones naming + badges, PollData one-vote rule + round-trip,
// DailyPlan per-day math, OfflineQueue, Moderation, CommunityMessage
// anonymity, and the Milestone model round-trip.
//
// NOTE: this file imports flutter_test only. The models under test
// (community_message.dart, milestone.dart) import cloud_firestore
// transitively for the Timestamp type, but no Firebase API is called here.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/data/syllabus.dart';
import 'package:hsc_revision_master/milestones.dart';
import 'package:hsc_revision_master/models/community_message.dart';
import 'package:hsc_revision_master/models/milestone.dart';
import 'package:hsc_revision_master/services/moderation.dart';
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
  // 3. Poll one-vote rule + counts / percentages
  // ------------------------------------------------------------------
  group('PollData voting', () {
    PollData buildPoll({Map<String, int>? votes}) => PollData(
          id: 'poll-1',
          question: 'Which chapter next?',
          options: ['Physics', 'Chemistry', 'Biology'],
          votes: votes,
        );

    test('voting twice by the same user overwrites instead of adding',
        () {
      final votes = <String, int>{};
      votes['user-1'] = 0; // first vote: Physics
      votes['user-1'] = 1; // re-vote: Chemistry (overwrites)
      final poll = buildPoll(votes: votes);
      expect(poll.votes.length, 1);
      expect(poll.votes['user-1'], 1);
      expect(poll.counts, [0, 1, 0]);
      expect(poll.counts.reduce((a, b) => a + b), 1,
          reason: 'counts sum to the number of distinct voters');
    });

    test('counts and percentages sum correctly when everyone voted',
        () {
      final poll = buildPoll(votes: {
        'u1': 0,
        'u2': 0,
        'u3': 1,
        'u4': 2,
      });
      expect(poll.counts, [2, 1, 1]);
      expect(poll.counts.reduce((a, b) => a + b), 4);
      expect(poll.percentages, [50.0, 25.0, 25.0]);
      expect(
        poll.percentages.reduce((a, b) => a + b),
        closeTo(100.0, 0.001),
      );
    });

    test('percentages are all 0 when nobody has voted', () {
      final poll = buildPoll();
      expect(poll.counts, [0, 0, 0]);
      expect(poll.percentages, [0.0, 0.0, 0.0]);
      expect(
        poll.percentages.reduce((a, b) => a + b),
        0.0,
      );
    });
  });

  // ------------------------------------------------------------------
  // 4. PollData toMap / fromMap round-trip
  // ------------------------------------------------------------------
  test('PollData toMap/fromMap round-trip preserves question, options, '
      'and votes', () {
    final original = PollData(
      id: 'poll-9',
      question: 'Best revision stage?',
      options: ['Archive', 'Recall', 'MCQ'],
      votes: {'u1': 0, 'u2': 2, 'u3': 2},
    );
    final restored = PollData.fromMap(original.toMap());
    expect(restored.id, original.id);
    expect(restored.question, original.question);
    expect(restored.options, original.options);
    expect(restored.votes, original.votes);
  });

  // ------------------------------------------------------------------
  // 5. Per-day target math (DailyPlan)
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
  // 6. Offline queue
  // ------------------------------------------------------------------
  group('OfflineQueue', () {
    OfflineQueue buildQueue() {
      final queue = OfflineQueue();
      queue.enqueue({'type': 'message', 'text': 'first'});
      queue.enqueue({'type': 'message', 'text': 'second'});
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
      expect(restored.pending[0]['type'], 'message');
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
  // 7. Moderation
  // ------------------------------------------------------------------
  group('Moderation', () {
    test('flags a message containing a blocked word, case-insensitive',
        () {
      expect(Moderation.isFlagged('FREE MONEY here'), isTrue);
      expect(Moderation.isFlagged('free money here'), isTrue);
      expect(Moderation.isFlagged('Free Money here'), isTrue);
    });

    test('does not flag a normal revision message', () {
      expect(
        Moderation.isFlagged('Physics chapter 1 done'),
        isFalse,
      );
      expect(
        Moderation.flagReason('Physics chapter 1 done'),
        isNull,
      );
    });

    test('flagReason names the matched word', () {
      final reason = Moderation.flagReason('FREE MONEY here');
      expect(reason, isNotNull);
      expect(reason, contains('free money'));
    });
  });

  // ------------------------------------------------------------------
  // 8. Community messages always show their author + photo encoding
  // ------------------------------------------------------------------
  group('CommunityMessage identity', () {
    CommunityMessage buildMessage() => CommunityMessage(
          id: 'msg-1',
          authorId: 'user-42',
          authorName: 'Rafi',
          text: 'Physics chapter 1 done',
          type: MessageType.text,
          timestamp: DateTime.utc(2026, 11, 23, 12, 0),
        );

    test('round-trip preserves authorId, authorName and text', () {
      final original = buildMessage();
      // fromMap takes the doc id as a separate argument (it is not in
      // the map); the id is the message id.
      final restored = CommunityMessage.fromMap(
        original.id,
        original.toMap(),
      );
      expect(restored.authorId, 'user-42');
      expect(restored.authorName, 'Rafi');
      expect(restored.text, 'Physics chapter 1 done');
      expect(
        restored.timestamp.millisecondsSinceEpoch,
        original.timestamp.millisecondsSinceEpoch,
      );
    });

    test('a lone image URL as text becomes a photo message', () {
      const url = 'https://example.blob.core.windows.net/notes/photo.jpg';
      final message = CommunityMessage.fromMap('msg-2', {
        'author_id': 'user-42',
        'author_name': 'Rafi',
        'text': url,
        'created_at': '2026-11-24T07:00:00.000Z',
      });
      expect(message.type, MessageType.photo);
      expect(message.photoUrl, url);
      expect(message.text, isNull);
    });

    test('isImageUrl rejects text with spaces and non-image URLs', () {
      expect(
        CommunityMessage.isImageUrl('https://example.com/a.jpg'),
        isTrue,
      );
      expect(
        CommunityMessage.isImageUrl('https://example.com/a.jpg?x=1'),
        isTrue,
      );
      expect(
        CommunityMessage.isImageUrl('look at https://example.com/a.jpg'),
        isFalse,
      );
      expect(
        CommunityMessage.isImageUrl('https://example.com/page'),
        isFalse,
      );
      expect(CommunityMessage.isImageUrl('hello'), isFalse);
    });

    test('backend poll votes {optionIndex: [uids]} invert to {uid: index}',
        () {
      final poll = PollData.fromMap({
        'id': 'poll-1',
        'question': 'Which subject first?',
        'options': ['Physics', 'Chemistry'],
        'votes': {
          '0': ['u1', 'u2'],
          '1': ['u3'],
        },
      });
      expect(poll.votes, {'u1': 0, 'u2': 0, 'u3': 1});
      expect(poll.counts, [2, 1]);
    });
  });

  // ------------------------------------------------------------------
  // 9. Milestone model round-trip
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
