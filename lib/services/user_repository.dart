import 'dart:async';
import 'dart:typed_data';

import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Per-user account data, backed by the custom backend.
///
/// A single user is fetched via GET /api/users/:id (email is hidden
/// unless it is my own row or I am an admin) and cached per id.
/// [userStream] emits the cached row once (or the fetch result);
/// there is no Realtime users table to subscribe to.
///
/// This is the signed-in user's own account screen data only — there
/// is no community left in the app: no leaderboard, no following,
/// no profile privacy.
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
        isAdmin: current.isAdmin,
        streak: current.streak,
        totalChaptersDone: current.totalChaptersDone,
        milestoneIds: current.milestoneIds,
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
