import 'dart:async';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'offline_queue.dart';

/// Per-chapter special notes: text, photo, or text + photo, saved per
/// chapter to help next-time revision.
///
/// Local cache lives in SharedPreferences under key 'chapter-notes-v1'
/// (JSON map chapterId -> {text, localPhotoPath, photoUrl}) so notes work
/// fully offline. When signed in, photos are uploaded via
/// POST /api/upload?kind=note and the note is mirrored to
/// POST /api/notes.
///
/// Backend mapping: the `notes` table has no chapter_id column, so the
/// chapter id travels in the `title` field (the chapter-note UI never
/// shows a title). GET /api/notes returns all my notes; [getNote]
/// picks the newest row whose title is the chapter id. Each save
/// creates a new row — the newest one wins, older rows are ignored.
class NotesRepository {
  NotesRepository._();

  static final NotesRepository instance = NotesRepository._();

  static const String cacheKey = 'chapter-notes-v1';

  Future<Map<String, dynamic>> _readCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Corrupt cache must never crash the app.
    }
    return {};
  }

  Future<void> _writeCache(Map<String, dynamic> cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(cacheKey, jsonEncode(cache));
  }

  Future<void> saveNote({
    required String chapterId,
    required String text,
    String? localPhotoPath,
  }) async {
    final cache = await _readCache();
    final existing =
        (cache[chapterId] as Map?)?.cast<String, dynamic>() ?? {};

    String? photoUrl = existing['photoUrl'] as String?;
    if (localPhotoPath != null && localPhotoPath.isNotEmpty) {
      if (AuthService.instance.isSignedIn) {
        try {
          final bytes = await XFile(localPhotoPath).readAsBytes();
          final res = await ApiClient.instance.uploadImage(
            filename: 'note_$chapterId.jpg',
            kind: 'note',
            bytes: bytes,
            contentType: 'image/jpeg',
          );
          photoUrl = (res['url'] as String?) ?? photoUrl;
        } catch (_) {
          // Upload failed — keep the local path so the photo is not lost.
          photoUrl = null;
        }
      }
    }

    final note = <String, dynamic>{
      'text': text,
      'localPhotoPath': localPhotoPath ?? existing['localPhotoPath'],
      'photoUrl': photoUrl,
    };
    cache[chapterId] = note;
    await _writeCache(cache);

    // The server mirror is queued when offline (or when the write
    // fails) so SyncService replays it when the device is back online.
    // There is no guest mode: the app root requires login, so this
    // runs while signed in; a dead session just keeps the note in the
    // local cache until the next save.
    try {
      await ApiClient.instance.post(
        '/api/notes',
        auth: true,
        body: {
          'title': chapterId,
          'body': text,
          'photo_url': photoUrl,
        },
      );
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        await OfflineQueue.enqueueOp({
          'type': 'note',
          'chapterId': chapterId,
          'text': text,
          'localPhotoPath': note['localPhotoPath'],
        });
      }
      // Any other failure (e.g. session expired): the local cache
      // above is the source of truth, so the note is not lost.
    } catch (_) {
      // Same: local cache keeps the note.
    }
  }

  /// Returns `{'text': ..., 'photoUrl': ... or 'localPhotoPath': ...}`
  /// or null when no note exists for the chapter.
  Future<Map<String, dynamic>?> getNote(String chapterId) async {
    final cache = await _readCache();
    final local = (cache[chapterId] as Map?)?.cast<String, dynamic>();
    if (local != null) return local;

    if (!AuthService.instance.isSignedIn) return null;
    try {
      final res = await ApiClient.instance.get('/api/notes', auth: true);
      final rows = (res['notes'] as List?) ?? [];
      // Newest first from the server; the first row whose title is
      // this chapter id is the latest save for it.
      for (final row in rows) {
        if (row is! Map) continue;
        final map = row.cast<String, dynamic>();
        if ((map['title'] as String?) != chapterId) continue;
        return {
          'text': map['body'],
          'photoUrl': map['photo_url'],
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
