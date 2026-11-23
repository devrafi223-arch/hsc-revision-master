import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SinglePresenceState state(String key, List<Map<String, dynamic>> payloads) {
  return SinglePresenceState(
    key: key,
    presences: [
      for (final p in payloads)
        Presence(presenceRef: '$key-ref', payload: p),
    ],
  );
}

void main() {
  group('PresenceSnapshot.fromStates', () {
    test('collects online uids and other users who are typing', () {
      final snap = PresenceSnapshot.fromStates([
        state('k1', [
          {'uid': 'me', 'name': 'Rafi', 'typing': false},
        ]),
        state('k2', [
          {'uid': 'u2', 'name': 'Ani', 'typing': true},
        ]),
        state('k3', [
          {'uid': 'u3', 'name': 'Bristi', 'typing': false},
        ]),
      ], 'me');
      expect(snap.onlineUids, {'me', 'u2', 'u3'});
      expect(snap.typingNames, ['Ani']);
    });

    test('self typing is not reported', () {
      final snap = PresenceSnapshot.fromStates([
        state('k1', [
          {'uid': 'me', 'name': 'Rafi', 'typing': true},
        ]),
      ], 'me');
      expect(snap.typingNames, isEmpty);
    });

    test('entries without a uid are skipped', () {
      final snap = PresenceSnapshot.fromStates([
        state('k1', [
          {'name': 'Ghost', 'typing': true},
        ]),
        state('k2', [
          {'uid': 'u2', 'name': 'Ani', 'typing': true},
        ]),
      ], 'me');
      expect(snap.onlineUids, {'u2'});
      expect(snap.typingNames, ['Ani']);
    });

    test('empty state gives an empty snapshot', () {
      final snap = PresenceSnapshot.fromStates([], 'me');
      expect(snap.onlineUids, isEmpty);
      expect(snap.typingNames, isEmpty);
    });
  });
}
