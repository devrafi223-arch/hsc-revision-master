import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'supabase_init.dart';

/// Study groups joined by a 6-character code. Supabase tables `groups`
/// (rows carry a `code`, `name`, `owner_id`) + `group_members`
/// (the membership join table, replacing the old Firestore `members` array).
///
/// Offline: a created group is kept in SharedPreferences ('my-groups-v1')
/// and returned immediately; it is NOT synced to Supabase yet (sync of
/// group creation is a TODO for SyncService — only 'message' and 'note'
/// ops replay today).
class GroupsService {
  GroupsService._();

  static final GroupsService instance = GroupsService._();

  static const String _localGroupsKey = 'my-groups-v1';

  /// 6-char codes use no ambiguous characters (no 0/O, no 1/I).
  static const String _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  SupabaseClient get _db => SupabaseInit.client;

  String _newCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => _codeChars[random.nextInt(_codeChars.length)],
    ).join();
  }

  Future<List<Map<String, dynamic>>> _readLocalGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localGroupsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
      }
    } catch (_) {
      // Corrupt local data must never crash the app.
    }
    return [];
  }

  Future<void> _writeLocalGroups(
    List<Map<String, dynamic>> groups,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localGroupsKey, jsonEncode(groups));
  }

  /// Creates a group and returns its 6-char uppercase join code.
  Future<String> createGroup(String name) async {
    final uid = AuthService.instance.currentUid;
    final code = _newCode();
    final now = DateTime.now().millisecondsSinceEpoch;
    final group = <String, dynamic>{
      'name': name,
      'code': code,
      'createdBy': uid,
      'members': uid == null ? <String>[] : [uid],
      'createdAt': now,
    };
    if (!SupabaseInit.isOnlineMode) {
      final local = await _readLocalGroups();
      local.add({...group, 'id': 'local-$code'});
      await _writeLocalGroups(local);
      return code;
    }
    final inserted = await _db
        .from('groups')
        .insert({
          'name': name,
          'code': code,
          'owner_id': uid,
        })
        .select('id')
        .single();
    final groupId = (inserted['id'] as Object?)?.toString() ?? 'local-$code';
    if (uid != null) {
      try {
        await _db.from('group_members').insert({
          'group_id': groupId,
          'user_id': uid,
        });
      } catch (_) {
        // Membership insert is best effort; the group itself exists.
      }
    }
    // Keep a local copy too so myGroups() works while offline later.
    final local = await _readLocalGroups();
    local.add({...group, 'id': groupId});
    await _writeLocalGroups(local);
    return code;
  }

  /// Joins the group with this [code]. Returns true on success, false
  /// when no group has that code (or when offline and unknown locally).
  Future<bool> joinGroup(String code) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return false;
    final normalized = code.trim().toUpperCase();
    if (!SupabaseInit.isOnlineMode) {
      final local = await _readLocalGroups();
      final match = local.where((g) => g['code'] == normalized).toList();
      if (match.isEmpty) return false;
      final group = match.first;
      final members =
          (group['members'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      if (!members.contains(uid)) {
        members.add(uid);
        group['members'] = members;
        await _writeLocalGroups(local);
      }
      return true;
    }
    final row = await _db
        .from('groups')
        .select('id, name, code')
        .eq('code', normalized)
        .limit(1)
        .maybeSingle();
    if (row == null) return false;
    final groupId = (row['id'] as Object?)?.toString();
    if (groupId == null) return false;
    try {
      await _db.from('group_members').insert({
        'group_id': groupId,
        'user_id': uid,
      });
    } catch (_) {
      // Already a member (PK conflict) — joining still succeeded.
    }
    final local = await _readLocalGroups();
    if (local.every((g) => g['id'] != groupId)) {
      local.add({
        ...row.cast<String, dynamic>(),
        'id': groupId,
        'createdBy': null,
        'members': [uid],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      await _writeLocalGroups(local);
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> _fetchMyGroups(String uid) async {
    final memberRows = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', uid);
    final groupIds = (memberRows as List)
        .whereType<Map>()
        .map((r) => (r['group_id'] as Object?)?.toString())
        .whereType<String>()
        .toList();
    if (groupIds.isEmpty) return [];
    final rows = await _db
        .from('groups')
        .select()
        .inFilter('id', groupIds);
    return (rows as List)
        .whereType<Map>()
        .map((row) {
          final map = row.cast<String, dynamic>();
          return {...map, 'id': (map['id'] as Object?)?.toString()};
        })
        .toList();
  }

  /// Groups the current user is a member of. Offline → the locally kept
  /// list (groups created/joined on this device).
  Stream<List<Map<String, dynamic>>> myGroups() {
    final uid = AuthService.instance.currentUid;
    if (!SupabaseInit.isOnlineMode || uid == null) {
      return Stream.fromFuture(_readLocalGroups());
    }
    final controller =
        StreamController<List<Map<String, dynamic>>>();
    var closed = false;
    Future<void> emit() async {
      try {
        final groups = await _fetchMyGroups(uid);
        if (!closed) controller.add(groups);
      } catch (_) {
        if (!closed) controller.add(await _readLocalGroups());
      }
    }

    unawaited(emit());
    final channel = _db
        .channel('public:group_members:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          callback: (_) => unawaited(emit()),
        )
        .subscribe();
    controller.onCancel = () async {
      closed = true;
      await channel.unsubscribe();
      await controller.close();
    };
    return controller.stream;
  }
}
