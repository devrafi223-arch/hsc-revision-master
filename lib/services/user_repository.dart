import 'dart:async';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Per-user profile data, backed by the custom backend.
///
/// A single user is fetched via GET /api/users/:id (email is hidden
/// unless it is my own row or I am an admin) and cached per id, so
/// the community feed does not hit the network on every rebuild.
/// [userStream] emits the cached row once (or the fetch result);
/// there is no Realtime users table to subscribe to.
///
/// The leaderboard comes from GET /api/leaderboard?range= (top 50;
/// rows carry `score`). The weekly range counts milestones in the
/// last 7 days, so it is a real activity leaderboard — not a
/// snapshot of total chapters.
///
/// Follow and privacy are LOCAL-ONLY: the backend has no endpoint
/// for them, so they live in the local cache and SharedPreferences
/// ('followed-users-v1') and apply to the profile screen only.
class UserRepository {
  UserRepository._();

  static final UserRepository instance = UserRepository._();

  final Map<String, AppUser> _localCache = {};

  AppUser? currentUser() => AuthService.instance.currentUser;

  /// The current user's id (the JWT uid), or null when not signed in.
  /// There is no anonymous fallback id — the app shows the login
  /// screen when there is no valid JWT.
  String? currentUid() => AuthService.instance.currentUid;

  /// Saves a profile row in the local cache only. There is no
  /// profile-update endpoint on the backend, so this never writes
  /// to the server.
  Future<void> saveUser(AppUser u) async {
    _localCache[u.id] = u;
  }

  /// Emits the cached profile once (or the fetched one). No live
  /// stream: the backend has no Realtime.
  Stream<AppUser?> userStream(String uid) async* {
    yield await getUser(uid);
  }

  /// Fetches a user (cached per id). Offline / not signed in → the
  /// local cache, or null.
  Future<AppUser?> getUser(String uid) async {
    final cached = _localCache[uid];
    if (cached != null) return cached;
    if (!AuthService.instance.isSignedIn) return null;
    try {
      final res = await ApiClient.instance.get('/api/users/$uid', auth: true);
      final map = res['user'] as Map?;
      if (map == null) return null;
      final user = AppUser.fromMap(
        (map['id'] as String?) ?? uid,
        map.cast<String, dynamic>(),
      );
      _localCache[uid] = user;
      return user;
    } catch (_) {
      return _localCache[uid];
    }
  }

  /// Weekly top 50 by milestones in the last 7 days. Offline → [].
  Future<List<AppUser>> leaderboardWeekly({int limit = 10}) async {
    final users = await _leaderboard(range: 'weekly');
    return users.take(limit).toList();
  }

  Future<List<AppUser>> leaderboardAll({int limit = 10}) async {
    final users = await _leaderboard(range: 'all');
    return users.take(limit).toList();
  }

  Future<List<AppUser>> _leaderboard({required String range}) async {
    try {
      final res = await ApiClient.instance.get(
        '/api/leaderboard',
        query: {'range': range},
      );
      final rows = (res['leaderboard'] as List?) ?? [];
      return rows
          .whereType<Map>()
          .map((row) {
            final map = row.cast<String, dynamic>();
            return AppUser.fromMap(
              (map['id'] as String?) ?? '',
              map,
            );
          })
          .where((u) => u.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Follow is LOCAL-ONLY (no backend endpoint): [uid] follows
  /// [targetUid] on this device.
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final followed = (prefs.getStringList('followed-users-v1') ?? [])
          .toSet();
      followed.add(targetUid);
      await prefs.setStringList('followed-users-v1', followed.toList());
    } catch (_) {
      // Best effort; the in-memory cache above is kept.
    }
  }

  /// Privacy is LOCAL-ONLY (no backend endpoint): the update is
  /// applied to the cached user and kept for this session.
  Future<void> updatePrivacy(
    String uid, {
    String? profileVisibility,
    String? photoVisibility,
  }) async {
    final me = _localCache[uid];
    if (me != null) {
      _localCache[uid] = AppUser(
        id: me.id,
        name: me.name,
        email: me.email,
        photoUrl: me.photoUrl,
        coverUrl: me.coverUrl,
        profileVisibility: profileVisibility ?? me.profileVisibility,
        photoVisibility: photoVisibility ?? me.photoVisibility,
        isAdmin: me.isAdmin,
        streak: me.streak,
        totalChaptersDone: me.totalChaptersDone,
        milestoneIds: me.milestoneIds,
        followingIds: me.followingIds,
      );
    }
  }

  /// Updates the cached photo for [uid]. The server photo is set by
  /// [uploadProfilePhoto] instead — this only refreshes the local
  /// cache so avatars update immediately.
  Future<void> updatePhoto(String uid, String photoUrl) async {
    final current = _localCache[uid];
    if (current != null) {
      _localCache[uid] = AppUser(
        id: current.id,
        name: current.name,
        email: current.email,
        photoUrl: photoUrl,
        coverUrl: current.coverUrl,
        profileVisibility: current.profileVisibility,
        photoVisibility: current.photoVisibility,
        isAdmin: current.isAdmin,
        streak: current.streak,
        totalChaptersDone: current.totalChaptersDone,
        milestoneIds: current.milestoneIds,
        followingIds: current.followingIds,
      );
    }
  }

  /// Uploads a profile photo via POST /api/upload?kind=profile and
  /// returns its Blob URL. The server also stores the URL on the
  /// user's row, so a GET /api/auth/me afterwards shows the new
  /// photo. Throws [ApiException] when not signed in or offline.
  Future<String> uploadProfilePhoto(String uid, Uint8List bytes) async {
    final res = await ApiClient.instance.uploadImage(
      filename: 'profile_$uid.jpg',
      kind: 'profile',
      bytes: bytes,
      contentType: 'image/jpeg',
    );
    final url = (res['url'] as String?) ?? '';
    if (url.isEmpty) {
      throw ApiException('SERVER_ERROR', 'Photo upload failed.');
    }
    return url;
  }
}
