import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'firebase_init.dart';

/// User profiles in Firestore collection `users` (doc id = uid).
///
/// All Firestore calls are guarded: while [FirebaseInit.isOnlineMode] is
/// false, a local in-memory cache is used instead and methods never throw.
class UserRepository {
  UserRepository._();

  static final UserRepository instance = UserRepository._();

  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');

  final Map<String, AppUser> _localCache = {};

  Future<void> saveUser(AppUser u) async {
    _localCache[u.id] = u;
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await _users.doc(u.id).set(u.toMap(), SetOptions(merge: true));
    } catch (_) {
      // Offline/cache fallback: the local copy above is kept.
    }
  }

  Stream<AppUser?> userStream(String uid) {
    if (!FirebaseInit.isOnlineMode) {
      return Stream<AppUser?>.value(_localCache[uid]);
    }
    return _users.doc(uid).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      return AppUser.fromMap(doc.id, data);
    });
  }

  Future<AppUser?> getUser(String uid) async {
    if (!FirebaseInit.isOnlineMode) return _localCache[uid];
    try {
      final doc = await _users.doc(uid).get();
      final data = doc.data();
      if (data == null) return _localCache[uid];
      final user = AppUser.fromMap(doc.id, data);
      _localCache[uid] = user;
      return user;
    } catch (_) {
      return _localCache[uid];
    }
  }

  /// Weekly top 10 by chapters finished.
  ///
  /// TODO: the "weekly" filter is not implemented yet — Firestore needs a
  /// dedicated weekly counter field (e.g. `chaptersDoneThisWeek` plus a
  /// `weekStart` timestamp, reset by a scheduled job / Cloud Function).
  /// Until that field exists this orders by the all-time
  /// `totalChaptersDone` count.
  Future<List<AppUser>> leaderboardWeekly({int limit = 10}) async {
    if (!FirebaseInit.isOnlineMode) {
      final users = _localCache.values.toList()
        ..sort((a, b) => b.totalChaptersDone.compareTo(a.totalChaptersDone));
      return users.take(limit).toList();
    }
    try {
      final snapshot = await _users
          .orderBy('totalChaptersDone', descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> follow(String uid, String targetUid) async {
    final me = _localCache[uid];
    if (me != null && !me.followingIds.contains(targetUid)) {
      _localCache[uid] = AppUser(
        id: me.id,
        name: me.name,
        email: me.email,
        photoUrl: me.photoUrl,
        coverUrl: me.coverUrl,
        profileVisibility: me.profileVisibility,
        photoVisibility: me.photoVisibility,
        isAdmin: me.isAdmin,
        streak: me.streak,
        totalChaptersDone: me.totalChaptersDone,
        milestoneIds: me.milestoneIds,
        followingIds: [...me.followingIds, targetUid],
      );
    }
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await _users.doc(uid).update({
        'followingIds': FieldValue.arrayUnion([targetUid]),
      });
    } catch (_) {
      // Kept in the local cache above; syncs on the next saveUser.
    }
  }

  Future<void> updatePrivacy(
    String uid, {
    String? profileVisibility,
    String? photoVisibility,
  }) async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      final updates = <String, dynamic>{};
      if (profileVisibility != null) {
        updates['profileVisibility'] = profileVisibility;
      }
      if (photoVisibility != null) {
        updates['photoVisibility'] = photoVisibility;
      }
      if (updates.isNotEmpty) await _users.doc(uid).update(updates);
    } catch (_) {
      // Privacy update is best effort; the local cache keeps the old value.
    }
  }

  Future<void> updateCover(String uid, String coverUrl) async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await _users.doc(uid).update({'coverUrl': coverUrl});
    } catch (_) {
      // Best effort.
    }
  }
}
