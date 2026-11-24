import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Study groups joined by a 6-character code (server-generated).
///
/// The backend owns groups: POST /api/groups creates one (the code
/// comes back in the response), POST /api/groups/join joins by code,
/// GET /api/groups lists the signed-in user's groups.
///
/// Offline: the last fetched list is kept in SharedPreferences
/// ('my-groups-v1') and returned when the network is down. Creating
/// or joining a group needs the network — the code lives on the
/// server, so a local-only group would be useless to anyone else.
class GroupsService {
  GroupsService._();

  static final GroupsService instance = GroupsService._();

  static const String _localGroupsKey = 'my-groups-v1';

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
  /// Throws [ApiException] when offline or not signed in.
  Future<String> createGroup(String name) async {
    final res = await ApiClient.instance.post(
      '/api/groups',
      auth: true,
      body: {'name': name},
    );
    final group = res['group'] as Map?;
    final code = (group?['code'] as String?) ?? '';
    if (code.isEmpty) {
      throw ApiException('SERVER_ERROR', 'Could not create the group.');
    }
    // Keep a local copy too so myGroups() works while offline later.
    final local = await _readLocalGroups();
    local.add({
      'id': (group?['id'] as String?) ?? 'local-$code',
      'name': name,
      'code': code,
      'createdBy': AuthService.instance.currentUid,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _writeLocalGroups(local);
    return code;
  }

  /// Joins the group with this [code]. Returns true on success, false
  /// when no group has that code. Throws [ApiException] when offline
  /// or not signed in.
  Future<bool> joinGroup(String code) async {
    final normalized = code.trim().toUpperCase();
    try {
      final res = await ApiClient.instance.post(
        '/api/groups/join',
        auth: true,
        body: {'code': normalized},
      );
      final group = res['group'] as Map?;
      if (group == null) return false;
      final local = await _readLocalGroups();
      final groupId = (group['id'] as String?) ?? '';
      if (groupId.isNotEmpty &&
          local.every((g) => g['id'] != groupId)) {
        local.add({
          'id': groupId,
          'name': (group['name'] as String?) ?? 'Group',
          'code': (group['code'] as String?) ?? normalized,
          'createdBy': group['created_by'],
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
        await _writeLocalGroups(local);
      }
      return true;
    } on ApiException catch (e) {
      if (e.code == 'NOT_FOUND') return false;
      rethrow;
    }
  }

  /// Groups the current user is a member of. Offline → the locally
  /// kept list (groups created/joined on this device while signed in).
  /// Not signed in → empty: there is no guest mode.
  Stream<List<Map<String, dynamic>>> myGroups() async* {
    if (!AuthService.instance.isSignedIn) {
      yield [];
      return;
    }
    try {
      final res = await ApiClient.instance.get('/api/groups', auth: true);
      final rows = (res['groups'] as List?) ?? [];
      final groups = rows
          .whereType<Map>()
          .map((row) {
            final map = row.cast<String, dynamic>();
            return {...map, 'id': (map['id'] as Object?)?.toString()};
          })
          .toList();
      await _writeLocalGroups(groups);
      yield groups;
    } catch (_) {
      yield await _readLocalGroups();
    }
  }
}
