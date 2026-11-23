import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_message.dart';
import 'auth_service.dart';
import 'firebase_init.dart';
import 'moderation.dart';
import 'offline_queue.dart';
import 'user_repository.dart';

/// Universal community (groupId == null) + group chats (groupId set).
/// Firestore collection `messages`.
///
/// Moderation: [Moderation.isFlagged] runs on every text/photo message.
/// A flagged message is stored with flagged=true and its text replaced by
/// 'Removed by moderation'; the original text is kept ONLY in the local
/// offline queue under 'flaggedOriginal' and is never uploaded.
///
/// Offline: writes are enqueued into [OfflineQueue] and persisted as JSON
/// in SharedPreferences under key 'offline-queue-v1'; [SyncService] replays
/// them when the device is back online.
class CommunityService {
  CommunityService._();

  static final CommunityService instance = CommunityService._();

  /// SharedPreferences key holding the offline queue JSON.
  static const String queueKey = 'offline-queue-v1';

  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance.collection('messages');

  // -- offline queue persistence (shared with SyncService) -------------

  static Future<OfflineQueue> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    return OfflineQueue.fromJsonString(prefs.getString(queueKey) ?? '');
  }

  static Future<void> persistQueue(OfflineQueue queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(queueKey, queue.toJson());
  }

  Future<void> _enqueue(Map<String, dynamic> op) async {
    await enqueueOp(op);
  }

  /// Enqueues one op into the shared offline queue (persisted as JSON).
  /// Used by other repositories (e.g. NotesRepository) that need their
  /// writes replayed by SyncService.
  static Future<void> enqueueOp(Map<String, dynamic> op) async {
    final queue = await loadQueue();
    queue.enqueue(op);
    await persistQueue(queue);
  }

  // -- helpers ----------------------------------------------------------

  Future<(String, String)> _author() async {
    final uid = AuthService.instance.currentUid ?? 'anonymous';
    var name = 'Student';
    try {
      final user = await UserRepository.instance.getUser(uid);
      if (user != null && user.name.isNotEmpty) name = user.name;
    } catch (_) {
      // Name lookup is best effort.
    }
    return (uid, name);
  }

  String _newId() =>
      'local-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

  Future<String> _uploadBytes({
    required Uint8List bytes,
    required String storagePath,
    required String contentType,
  }) async {
    final ref = FirebaseStorage.instance.ref().child(storagePath);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  // -- reading ----------------------------------------------------------

  /// Newest first. Offline → an empty list (queued messages live in the
  /// offline queue until they sync).
  ///
  /// NOTE: results are sorted client-side so no composite Firestore index
  /// is needed for the groupId filter + timestamp order.
  Stream<List<CommunityMessage>> messagesStream({String? groupId}) {
    if (!FirebaseInit.isOnlineMode) return Stream.value([]);
    return _messages
        .where('groupId', isEqualTo: groupId)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => CommunityMessage.fromMap(doc.id, doc.data()))
          .toList();
      messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return messages;
    });
  }

  // -- sending ----------------------------------------------------------

  Future<void> sendText(
    String text, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    final flagged = Moderation.isFlagged(text);
    final reason = flagged ? Moderation.flagReason(text) : null;
    final storedText = flagged ? 'Removed by moderation' : text;

    if (!FirebaseInit.isOnlineMode) {
      final op = <String, dynamic>{
        'type': 'message',
        'messageType': 'text',
        'text': storedText,
        'authorId': uid,
        'authorName': name,
        'groupId': groupId,
        'flagged': flagged,
        'flagReason': reason,
        'isAnonymous': anonymous,
      };
      // Original text lives ONLY in the local queue, never uploaded.
      if (flagged) op['flaggedOriginal'] = text;
      await _enqueue(op);
      return;
    }

    await _messages.add({
      'authorId': uid,
      'authorName': name,
      'text': storedText,
      'type': 'text',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'pinned': false,
      'reactions': <String, int>{},
      'bookmarkedBy': <String>[],
      'flagged': flagged,
      'flagReason': reason,
      'groupId': groupId,
      'isAnonymous': anonymous,
    });
  }

  Future<void> sendPhoto(
    String localPath, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    if (!FirebaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'message',
        'messageType': 'photo',
        'localPath': localPath,
        'authorId': uid,
        'authorName': name,
        'groupId': groupId,
        'isAnonymous': anonymous,
      });
      return;
    }
    final bytes = await XFile(localPath).readAsBytes();
    final url = await _uploadBytes(
      bytes: bytes,
      storagePath:
          'community/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      contentType: 'image/jpeg',
    );
    await _messages.add({
      'authorId': uid,
      'authorName': name,
      'photoUrl': url,
      'type': 'photo',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'pinned': false,
      'reactions': <String, int>{},
      'bookmarkedBy': <String>[],
      'flagged': false,
      'groupId': groupId,
      'isAnonymous': anonymous,
    });
  }

  Future<void> sendVoice(
    String localPath,
    int seconds, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    if (!FirebaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'message',
        'messageType': 'voice',
        'localPath': localPath,
        'seconds': seconds,
        'authorId': uid,
        'authorName': name,
        'groupId': groupId,
        'isAnonymous': anonymous,
      });
      return;
    }
    final bytes = await XFile(localPath).readAsBytes();
    final url = await _uploadBytes(
      bytes: bytes,
      storagePath:
          'community/voice/$uid/${DateTime.now().millisecondsSinceEpoch}.m4a',
      contentType: 'audio/m4a',
    );
    await _messages.add({
      'authorId': uid,
      'authorName': name,
      'voiceUrl': url,
      'text': 'Voice message ($seconds s)',
      'type': 'voice',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'pinned': false,
      'reactions': <String, int>{},
      'bookmarkedBy': <String>[],
      'flagged': false,
      'groupId': groupId,
      'isAnonymous': anonymous,
    });
  }

  Future<void> sendPoll(
    String question,
    List<String> options, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    final poll = PollData(
      id: _newId(),
      question: question,
      options: options,
    );
    if (!FirebaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'message',
        'messageType': 'poll',
        'poll': poll.toMap(),
        'authorId': uid,
        'authorName': name,
        'groupId': groupId,
        'isAnonymous': anonymous,
      });
      return;
    }
    await _messages.add({
      'authorId': uid,
      'authorName': name,
      'poll': poll.toMap(),
      'type': 'poll',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'pinned': false,
      'reactions': <String, int>{},
      'bookmarkedBy': <String>[],
      'flagged': false,
      'groupId': groupId,
      'isAnonymous': anonymous,
    });
  }

  // -- interactions -----------------------------------------------------

  /// One vote per user: the Firestore transaction writes
  /// votes[currentUid] = optionIndex, overwriting any previous vote.
  Future<void> vote(String messageId, int optionIndex) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null || !FirebaseInit.isOnlineMode) return;
    final ref = _messages.doc(messageId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final data = doc.data();
      if (data == null) return;
      final poll = data['poll'];
      if (poll is! Map) return;
      final votes = Map<String, dynamic>.from(poll['votes'] as Map? ?? {});
      votes[uid] = optionIndex;
      tx.update(ref, {
        'poll.votes': votes,
      });
    });
  }

  Future<void> react(String messageId, String emoji) async {
    if (!FirebaseInit.isOnlineMode) return;
    final ref = _messages.doc(messageId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final data = doc.data();
      if (data == null) return;
      final reactions =
          Map<String, dynamic>.from(data['reactions'] as Map? ?? {});
      reactions[emoji] = ((reactions[emoji] as num?)?.toInt() ?? 0) + 1;
      tx.update(ref, {'reactions': reactions});
    });
  }

  Future<void> reply(
    String messageId,
    String text,
    String replyToText, {
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    final flagged = Moderation.isFlagged(text);
    final storedText = flagged ? 'Removed by moderation' : text;
    if (!FirebaseInit.isOnlineMode) {
      final op = <String, dynamic>{
        'type': 'message',
        'messageType': 'text',
        'text': storedText,
        'authorId': uid,
        'authorName': name,
        'isAnonymous': anonymous,
        'replyToId': messageId,
        'replyToText': replyToText,
        'flagged': flagged,
        'flagReason': flagged ? Moderation.flagReason(text) : null,
      };
      if (flagged) op['flaggedOriginal'] = text;
      await _enqueue(op);
      return;
    }
    await _messages.add({
      'authorId': uid,
      'authorName': name,
      'isAnonymous': anonymous,
      'text': storedText,
      'type': 'text',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'replyToId': messageId,
      'replyToText': replyToText,
      'pinned': false,
      'reactions': <String, int>{},
      'bookmarkedBy': <String>[],
      'flagged': flagged,
      'flagReason': flagged ? Moderation.flagReason(text) : null,
    });
  }

  Future<void> togglePin(String messageId, bool pinned) async {
    if (!FirebaseInit.isOnlineMode) return;
    await _messages.doc(messageId).update({'pinned': pinned});
  }

  Future<void> toggleBookmark(String messageId) async {
    final uid = AuthService.instance.currentUid;
    if (uid == null || !FirebaseInit.isOnlineMode) return;
    final ref = _messages.doc(messageId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final data = doc.data();
      if (data == null) return;
      final bookmarked =
          (data['bookmarkedBy'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      if (bookmarked.contains(uid)) {
        tx.update(ref, {
          'bookmarkedBy': FieldValue.arrayRemove([uid]),
        });
      } else {
        tx.update(ref, {
          'bookmarkedBy': FieldValue.arrayUnion([uid]),
        });
      }
    });
  }

  Future<void> report(String messageId, String reason) async {
    final uid = AuthService.instance.currentUid;
    if (!FirebaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'report',
        'messageId': messageId,
        'reason': reason,
        'reporterUid': uid,
      });
      return;
    }
    await FirebaseFirestore.instance.collection('reports').add({
      'messageId': messageId,
      'reporterUid': uid,
      'reason': reason,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _messages.doc(messageId).update({
      'flagged': true,
      'flagReason': reason,
    });
  }

  Future<void> blockUser(String uid) async {
    final myUid = AuthService.instance.currentUid;
    if (myUid == null) return;
    if (!FirebaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'block',
        'uid': myUid,
        'targetUid': uid,
      });
      return;
    }
    await FirebaseFirestore.instance.collection('users').doc(myUid).update({
      'blockedIds': FieldValue.arrayUnion([uid]),
    });
  }
}
