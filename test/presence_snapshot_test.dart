import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/presence_service.dart';

void main() {
  group('PresenceSnapshot.fromApi', () {
    test('collects online uids from GET /api/presence rows', () {
      final snap = PresenceSnapshot.fromApi([
        {
          'id': 'me',
          'display_name': 'Rafi',
          'last_seen_at': '2026-11-24T07:00:00.000Z',
        },
        {
          'id': 'u2',
          'display_name': 'Ani',
          'last_seen_at': '2026-11-24T07:00:30.000Z',
        },
        {
          'id': 'u3',
          'display_name': 'Bristi',
          'last_seen_at': '2026-11-24T07:01:00.000Z',
        },
      ]);
      expect(snap.onlineUids, {'me', 'u2', 'u3'});
    });

    test('rows without an id are skipped', () {
      final snap = PresenceSnapshot.fromApi([
        {'display_name': 'Ghost'},
        {'id': 'u2', 'display_name': 'Ani'},
        {'id': ''},
      ]);
      expect(snap.onlineUids, {'u2'});
    });

    test('duplicate ids collapse to one entry', () {
      final snap = PresenceSnapshot.fromApi([
        {'id': 'u2'},
        {'id': 'u2'},
      ]);
      expect(snap.onlineUids, {'u2'});
    });

    test('empty rows give an empty snapshot', () {
      final snap = PresenceSnapshot.fromApi([]);
      expect(snap.onlineUids, isEmpty);
    });
  });
}
