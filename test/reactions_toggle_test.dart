import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/models/community_message.dart';
import 'package:hsc_revision_master/services/community_service.dart';

void main() {
  group('toggleReactionIn (like toggle, one reaction per user)', () {
    test('first tap adds the user', () {
      final next = CommunityService.toggleReactionIn({}, '❤️', 'uid-1');
      expect(next['❤️'], ['uid-1']);
    });

    test('second tap by the same user removes it again', () {
      final liked =
          CommunityService.toggleReactionIn({}, '❤️', 'uid-1');
      final unliked =
          CommunityService.toggleReactionIn(liked, '❤️', 'uid-1');
      expect(unliked['❤️'], isEmpty);
    });

    test('other users keep their reactions', () {
      final liked =
          CommunityService.toggleReactionIn({}, '👍', 'uid-1');
      final liked2 =
          CommunityService.toggleReactionIn(liked, '👍', 'uid-2');
      expect(liked2['👍'], ['uid-1', 'uid-2']);
      final unliked1 =
          CommunityService.toggleReactionIn(liked2, '👍', 'uid-1');
      expect(unliked1['👍'], ['uid-2']);
    });

    test('legacy int count migrates to the owner list on first tap', () {
      final next = CommunityService.toggleReactionIn(
        {'❤️': 3},
        '❤️',
        'uid-9',
      );
      // The old anonymous count cannot be attributed to anyone, so
      // the toggle restarts the emoji from this user.
      expect(next['❤️'], ['uid-9']);
    });

    test('different emojis are independent', () {
      var map = CommunityService.toggleReactionIn({}, '❤️', 'uid-1');
      map = CommunityService.toggleReactionIn(map, '🎉', 'uid-1');
      expect(map['❤️'], ['uid-1']);
      expect(map['🎉'], ['uid-1']);
    });
  });

  group('CommunityMessage reaction parsing', () {
    CommunityMessage msg(Map<String, dynamic> row) =>
        CommunityMessage.fromMap('m1', row);

    test('new list shape gives counts and owners', () {
      final m = msg({
        'reactions': {
          '❤️': ['uid-1', 'uid-2'],
          '👍': [],
        },
        'author_id': 'a',
        'author_name': 'A',
        'created_at': '2026-11-24T00:00:00Z',
      });
      expect(m.reactions, {'❤️': 2, '👍': 0});
      expect(m.reactionUsers['❤️'], ['uid-1', 'uid-2']);
      expect(m.reactionUsers['👍'], isEmpty);
    });

    test('legacy int shape gives counts with no owners', () {
      final m = msg({
        'reactions': {'❤️': 3},
        'author_id': 'a',
        'author_name': 'A',
        'created_at': '2026-11-24T00:00:00Z',
      });
      expect(m.reactions, {'❤️': 3});
      expect(m.reactionUsers['❤️'], isNull);
    });

    test('toMap round-trips the owner lists', () {
      final m = msg({
        'reactions': {
          '❤️': ['uid-1'],
        },
        'author_id': 'a',
        'author_name': 'A',
        'created_at': '2026-11-24T00:00:00Z',
      });
      final back = CommunityMessage.fromMap('m1', m.toMap());
      expect(back.reactions, {'❤️': 1});
      expect(back.reactionUsers['❤️'], ['uid-1']);
    });
  });
}
