import 'dart:async';
import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';
import 'community_service.dart';
import 'supabase_init.dart';

/// Per-chapter special notes: text, photo, or text + photo, saved per
/// chapter to help next-time revision.
///
/// Local cache lives in SharedPreferences under key 'chapter-notes-v1'
/// (JSON map chapterId -> {text, localPhotoPath, photoUrl}) so notes work
/// fully offline. When online, photos are uploaded to Supabase Storage
/// bucket `notes` at `notes/<uid>/<chapterId>.jpg` and the public URL is
/// stored; note metadata is mirrored to the Supabase `notes` table
/// (one row per user + chapter, upserted on that key).
class NotesRepository {
  NotesRepository._();

  static final NotesRepository instance = NotesRepository._();

  static const String cacheKey = 'chapter-notes-v1';

  /// Public Storage bucket for note photos (see supabase/schema.sql).
  static const String _storageBucket = 'notes';

  SupabaseClient get _db => SupabaseInit.client;

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
    final uid = AuthService.instance.effectiveUid;
    final cache = await _readCache();
    final existing =
        (cache[chapterId] as Map?)?.cast<String, dynamic>() ?? {};

    String? photoUrl = existing['photoUrl'] as String?;
    if (localPhotoPath != null && localPhotoPath.isNotEmpty) {
      if (SupabaseInit.isOnlineMode && uid != null) {
        try {
          final bytes = await XFile(localPhotoPath).readAsBytes();
          final storagePath = 'notes/$uid/$chapterId.jpg';
          await _db.storage.from(_storageBucket).uploadBinary(
                storagePath,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          photoUrl =
              _db.storage.from(_storageBucket).getPublicUrl(storagePath);
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

    // The Supabase mirror is queued when offline (or when the write
    // fails) so SyncService replays it when the device is back online.
    if (!SupabaseInit.isOnlineMode) {
      await CommunityService.enqueueOp({
        'type': 'note',
        'chapterId': chapterId,
        'text': text,
        'localPhotoPath': note['localPhotoPath'],
      });
      return;
    }

    if (uid != null) {
      try {
        await _db.from('notes').upsert(
          {
            'user_id': uid,
            'chapter_id': chapterId,
            'text': text,
            'photo_url': photoUrl,
            'local_path': note['localPhotoPath'],
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'user_id,chapter_id',
        );
      } catch (_) {
        // Supabase mirror failed — queue it for the next sync instead of
        // silently losing the cloud copy.
        await CommunityService.enqueueOp({
          'type': 'note',
          'chapterId': chapterId,
          'text': text,
          'localPhotoPath': note['localPhotoPath'],
        });
      }
    }
  }

  /// Returns `{'text': ..., 'photoUrl': ... or 'localPhotoPath': ...}`
  /// or null when no note exists for the chapter.
  Future<Map<String, dynamic>?> getNote(String chapterId) async {
    final cache = await _readCache();
    final local = (cache[chapterId] as Map?)?.cast<String, dynamic>();
    if (local != null) return local;

    final uid = AuthService.instance.effectiveUid;
    if (!SupabaseInit.isOnlineMode || uid == null) return null;
    try {
      final row = await _db
          .from('notes')
          .select()
          .eq('user_id', uid)
          .eq('chapter_id', chapterId)
          .maybeSingle();
      if (row == null) return null;
      return {
        'text': row['text'],
        'photoUrl': row['photo_url'],
      };
    } catch (_) {
      return null;
    }
  }

  /// Emits whenever the note for [chapterId] changes. Offline → a single
  /// null event (the local cache is the source of truth there).
  Stream<void> watchNote(String chapterId) {
    final uid = AuthService.instance.effectiveUid;
    if (!SupabaseInit.isOnlineMode || uid == null) {
      return Stream<void>.value(null);
    }
    final controller = StreamController<void>();
    var closed = false;
    final channel = _db
        .channel('public:notes:$chapterId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chapter_id',
            value: chapterId,
          ),
          callback: (_) {
            if (!closed) controller.add(null);
          },
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
