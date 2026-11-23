import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'community_service.dart';
import 'firebase_init.dart';

/// Per-chapter special notes: text, photo, or text + photo, saved per
/// chapter to help next-time revision.
///
/// Local cache lives in SharedPreferences under key 'chapter-notes-v1'
/// (JSON map chapterId -> {text, localPhotoPath, photoUrl}) so notes work
/// fully offline. When online, photos are uploaded to Firebase Storage at
/// `notes/<uid>/<chapterId>.jpg` and the download URL is stored; note
/// metadata is mirrored to Firestore collection `notes`
/// (doc id `<uid>_<chapterId>`).
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
    final uid = AuthService.instance.currentUid;
    final cache = await _readCache();
    final existing =
        (cache[chapterId] as Map?)?.cast<String, dynamic>() ?? {};

    String? photoUrl = existing['photoUrl'] as String?;
    if (localPhotoPath != null && localPhotoPath.isNotEmpty) {
      if (FirebaseInit.isOnlineMode && uid != null) {
        try {
          final bytes = await XFile(localPhotoPath).readAsBytes();
          final ref = FirebaseStorage.instance
              .ref()
              .child('notes/$uid/$chapterId.jpg');
          await ref.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          photoUrl = await ref.getDownloadURL();
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

    // The Firestore mirror is queued when offline (or when the write
    // fails) so SyncService replays it when the device is back online.
    if (!FirebaseInit.isOnlineMode) {
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
        await FirebaseFirestore.instance
            .collection('notes')
            .doc('${uid}_$chapterId')
            .set({
          'uid': uid,
          'chapterId': chapterId,
          'text': text,
          'photoUrl': photoUrl,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {
        // Firestore mirror failed — queue it for the next sync instead of
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

    final uid = AuthService.instance.currentUid;
    if (!FirebaseInit.isOnlineMode || uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('notes')
          .doc('${uid}_$chapterId')
          .get();
      final data = doc.data();
      if (data == null) return null;
      return {
        'text': data['text'],
        'photoUrl': data['photoUrl'],
      };
    } catch (_) {
      return null;
    }
  }

  /// Emits whenever the note for [chapterId] changes. Offline → a single
  /// null event (the local cache is the source of truth there).
  Stream<void> watchNote(String chapterId) {
    final uid = AuthService.instance.currentUid;
    if (!FirebaseInit.isOnlineMode || uid == null) {
      return Stream<void>.value(null);
    }
    return FirebaseFirestore.instance
        .collection('notes')
        .doc('${uid}_$chapterId')
        .snapshots()
        .map((_) {});
  }
}
