import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'firebase_init.dart';

/// Study groups joined by a 6-character code. Firestore collection
/// `groups` (docs carry a `code` field, `members` uid list, `createdBy`).
///
/// Offline: a created group is kept in SharedPreferences ('my-groups-v1')
/// and returned immediately; it is NOT synced to Firestore yet (sync of
/// group creation is a TODO for SyncService — only 'message' and 'note'
/// ops replay today).
class GroupsService {
  GroupsService._();

  static final GroupsService instance = GroupsService._();

  static const String _localGroupsKey = 'my-groups-v1';

  /// 6-char codes use no ambiguous characters (no 0/O, no 1/I).
  static const String _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

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
    if (!FirebaseInit.isOnlineMode) {
      final local = await _readLocalGroups();
      local.add({...group, 'id': 'local-$code'});
      await _writeLocalGroups(local);
      return code;
    }
    final ref = await FirebaseFirestore.instance
        .collection('groups')
        .add(group);
    // Keep a local copy too so myGroups() works while offline later.
    final local = await _readLocalGroups();
    local.add({...group, 'id': ref.id});
    await _writeLocalGroups(local);
    return code;
  }

  /// Joins the group with this [code]. Returns true on success, false
  /// when no group has that code (or when offline and unknown locally).
  Future<bool> joinGroup(String code) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null) return false;
    final normalized = code.trim().toUpperCase();
    if (!FirebaseInit.isOnlineMode) {
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
    final snapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('code', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return false;
    final doc = snapshot.docs.first;
    await doc.reference.update({
      'members': FieldValue.arrayUnion([uid]),
    });
    final local = await _readLocalGroups();
    if (local.every((g) => g['id'] != doc.id)) {
      local.add({...doc.data(), 'id': doc.id});
      await _writeLocalGroups(local);
    }
    return true;
  }

  /// Groups the current user is a member of. Offline → the locally kept
  /// list (groups created/joined on this device).
  Stream<List<Map<String, dynamic>>> myGroups() {
    final uid = AuthService.instance.currentUid;
    if (!FirebaseInit.isOnlineMode || uid == null) {
      return Stream.fromFuture(_readLocalGroups());
    }
    return FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              return {...doc.data(), 'id': doc.id};
            }).toList());
  }
}
