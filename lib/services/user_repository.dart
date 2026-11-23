import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'supabase_init.dart';

/// User profiles in the Supabase `users` table (row id = Auth uid).
///
/// All Supabase calls are guarded: while [SupabaseInit.isOnlineMode] is
/// false, a local in-memory cache is used instead and methods never throw.
class UserRepository {
  UserRepository._();

  static final UserRepository instance = UserRepository._();

  SupabaseClient get _db => SupabaseInit.client;

  final Map<String, AppUser> _localCache = {};

  Future<void> saveUser(AppUser u) async {
    _localCache[u.id] = u;
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db.from('users').upsert({'id': u.id, ...u.toMap()});
    } catch (_) {
      // Offline/cache fallback: the local copy above is kept.
    }
  }

  Stream<AppUser?> userStream(String uid) {
    if (!SupabaseInit.isOnlineMode) {
      return Stream<AppUser?>.value(_localCache[uid]);
    }
    final controller = StreamController<AppUser?>();
    var closed = false;
    Future<void> emit() async {
      try {
        final user = await getUser(uid);
        if (!closed) controller.add(user);
      } catch (_) {
        // Keep the stream alive; the next Realtime event retries.
      }
    }
    unawaited(emit());
    final channel = _db
        .channel('public:users:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
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

  Future<AppUser?> getUser(String uid) async {
    if (!SupabaseInit.isOnlineMode) return _localCache[uid];
    try {
      final row = await _db
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return _localCache[uid];
      final user = AppUser.fromMap(uid, row);
      _localCache[uid] = user;
      return user;
    } catch (_) {
      return _localCache[uid];
    }
  }

  /// Weekly top 10 by chapters finished.
  ///
  /// TODO: the "weekly" filter is not implemented yet — Supabase needs a
  /// dedicated weekly counter field (e.g. `chapters_done_this_week` plus
  /// a `week_start` timestamp, reset by a scheduled job / Edge Function).
  /// Until that field exists this orders by the all-time
  /// `chapters_done` count.
  Future<List<AppUser>> leaderboardWeekly({int limit = 10}) async {
    if (!SupabaseInit.isOnlineMode) {
      final users = _localCache.values.toList()
        ..sort((a, b) => b.totalChaptersDone.compareTo(a.totalChaptersDone));
      return users.take(limit).toList();
    }
    try {
      final rows = await _db
          .from('users')
          .select()
          .order('chapters_done', ascending: false)
          .limit(limit);
      return rows.map((row) {
        final map = (row as Map).cast<String, dynamic>();
        return AppUser.fromMap(map['id'] as String? ?? '', map);
      }).toList();
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
    if (!SupabaseInit.isOnlineMode) return;
    try {
      final current = await getUser(uid);
      final following = [...?current?.followingIds];
      if (!following.contains(targetUid)) following.add(targetUid);
      await _db.from('users').update({
        'following_ids': following,
      }).eq('id', uid);
    } catch (_) {
      // Kept in the local cache above; syncs on the next saveUser.
    }
  }

  Future<void> updatePrivacy(
    String uid, {
    String? profileVisibility,
    String? photoVisibility,
  }) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      final updates = <String, dynamic>{};
      if (profileVisibility != null) {
        updates['privacy'] = profileVisibility;
      }
      if (photoVisibility != null) {
        updates['photo_privacy'] = photoVisibility;
      }
      if (updates.isNotEmpty) {
        await _db.from('users').update(updates).eq('id', uid);
      }
    } catch (_) {
      // Privacy update is best effort; the local cache keeps the old value.
    }
  }

  Future<void> updateCover(String uid, String coverUrl) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db.from('users').update({'cover_url': coverUrl}).eq('id', uid);
    } catch (_) {
      // Best effort.
    }
  }
}
