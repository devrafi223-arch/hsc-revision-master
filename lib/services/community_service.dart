import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/community_message.dart';
import 'auth_service.dart';
import 'moderation.dart';
import 'offline_queue.dart';
import 'supabase_init.dart';
import 'user_repository.dart';

/// Universal community (groupId == null) + group chats (groupId set).
/// Supabase table `messages`; polls live in the `polls` table and are
/// attached to their message when read.
///
/// Moderation: [Moderation.isFlagged] runs on every text/photo message.
/// A flagged message is stored with flagged=true and its text replaced by
/// 'Removed by moderation'; the original text is kept ONLY in the local
/// offline queue under 'flaggedOriginal' and is never uploaded.
///
/// Offline: writes are enqueued into [OfflineQueue] and persisted as JSON
/// in SharedPreferences under key 'offline-queue-v1'; [SyncService] replays
/// them when the device is back online.
///
/// Bookmarks are LOCAL ONLY (a Set of message ids in SharedPreferences
/// under 'bookmarked-messages-v1'): there is no bookmark column in the
/// `messages` table. [messagesStream] merges the local set into each
/// message's `bookmarkedBy` so the screens' bookmark filter keeps working.
class CommunityService {
  CommunityService._();

  static final CommunityService instance = CommunityService._();

  /// SharedPreferences key holding the offline queue JSON.
  static const String queueKey = 'offline-queue-v1';

  /// SharedPreferences key holding the local bookmarked message ids.
  static const String bookmarksKey = 'bookmarked-messages-v1';

  /// Storage bucket for community photos / voice messages. The schema
  /// documents a single public bucket named 'notes' (see supabase/schema.sql).
  static const String _storageBucket = 'notes';

  SupabaseClient get _db => SupabaseInit.client;

  /// Notifies live streams when a local-only change (e.g. a bookmark
  /// toggle) happens, so they re-emit with the merged local state.
  static final StreamController<void> _localChanges =
      StreamController<void>.broadcast();

  static void _notifyLocalChange() {
    if (!_localChanges.isClosed) _localChanges.add(null);
  }

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

  // -- local bookmarks ----------------------------------------------------

  Set<String> _bookmarkedIds = {};
  bool _bookmarksLoaded = false;

  Future<void> _loadBookmarks() async {
    if (_bookmarksLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _bookmarkedIds =
          (prefs.getStringList(bookmarksKey) ?? []).toSet();
    } catch (_) {
      _bookmarkedIds = {};
    }
    _bookmarksLoaded = true;
  }

  Future<void> _persistBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(bookmarksKey, _bookmarkedIds.toList());
    } catch (_) {
      // Bookmarks are best effort; the in-memory set is kept.
    }
  }

  // -- helpers ----------------------------------------------------------

  Future<(String, String)> _author() async {
    final uid = AuthService.instance.effectiveUid ?? 'anonymous';
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
    await _db.storage.from(_storageBucket).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _db.storage.from(_storageBucket).getPublicUrl(storagePath);
  }

  /// Reads the latest messages from Supabase (oldest first — ordered by
  /// `created_at` ascending), attaches each message's poll row, and merges
  /// the local bookmark set into `bookmarkedBy`.
  Future<List<CommunityMessage>> _fetchMessages({String? groupId}) async {
    await _loadBookmarks();
    final uid = AuthService.instance.effectiveUid;
    final query = _db.from('messages').select();
    // Filters go BEFORE order/limit: select() returns a FilterBuilder
    // (eq/isFilter live there); order()/limit() return a TransformBuilder.
    final List<dynamic> rows;
    if (groupId == null) {
      rows = await query
          .isFilter('group_id', null)
          .order('created_at', ascending: true)
          .limit(100);
    } else {
      rows = await query
          .eq('group_id', groupId)
          .order('created_at', ascending: true)
          .limit(100);
    }
    final maps = rows
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();

    // Attach polls: one `polls` row per poll message, keyed by message_id.
    if (maps.isNotEmpty) {
      final ids = maps.map((m) => m['id'].toString()).toList();
      try {
        final pollRows = await _db
            .from('polls')
            .select()
            .inFilter('message_id', ids);
        final byMessage = <String, Map<String, dynamic>>{};
        for (final row in (pollRows as List).whereType<Map>()) {
          final map = row.cast<String, dynamic>();
          byMessage[(map['message_id'] as Object?)?.toString() ?? ''] = {
            'id': map['id'],
            'question': map['question'],
            'options': map['options'],
            'votes': map['votes'],
          };
        }
        for (final m in maps) {
          final poll = byMessage[m['id'].toString()];
          if (poll != null) m['poll'] = poll;
        }
      } catch (_) {
        // Polls are best effort; messages still show without them.
      }
    }

    final messages = maps
        .map((m) => CommunityMessage.fromMap(m['id'].toString(), m))
        .toList();
    if (uid == null) return messages;
    // Merge local bookmarks so `message.bookmarkedBy` reflects this
    // device's bookmark set (bookmarks are local-only, see class doc).
    return messages
        .map(
          (m) => _bookmarkedIds.contains(m.id)
              ? CommunityMessage(
                  id: m.id,
                  authorId: m.authorId,
                  authorName: m.authorName,
                  authorPhoto: m.authorPhoto,
                  text: m.text,
                  photoUrl: m.photoUrl,
                  voiceUrl: m.voiceUrl,
                  replyToId: m.replyToId,
                  replyToText: m.replyToText,
                  type: m.type,
                  timestamp: m.timestamp,
                  poll: m.poll,
                  pinned: m.pinned,
                  reactions: m.reactions,
                  bookmarkedBy: [uid],
                  flagged: m.flagged,
                  flagReason: m.flagReason,
                  groupId: m.groupId,
                  isAnonymous: m.isAnonymous,
                )
              : m,
        )
        .toList();
  }

  // -- reading ----------------------------------------------------------

  /// Oldest first (ordered by `created_at` ascending). Offline → an empty
  /// list (queued messages live in the offline queue until they sync).
  ///
  /// NOTE: the old Firestore version returned newest-first; this version
  /// returns chronological order (oldest at the top, newest at the bottom),
  /// as the Supabase migration spec requires. Screens showing the feed
  /// may want to scroll to the bottom on new messages.
  Stream<List<CommunityMessage>> messagesStream({String? groupId}) {
    if (!SupabaseInit.isOnlineMode) return Stream.value([]);
    final controller = StreamController<List<CommunityMessage>>();
    var closed = false;
    Future<void> emit() async {
      try {
        final messages = await _fetchMessages(groupId: groupId);
        if (!closed) controller.add(messages);
      } catch (_) {
        // Keep the stream alive; the next Realtime event retries.
      }
    }

    unawaited(emit());
    final channel = _db
        .channel('public:messages:${groupId ?? 'all'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => unawaited(emit()),
        )
        .subscribe();
    final localSub = _localChanges.stream.listen((_) => unawaited(emit()));
    controller.onCancel = () async {
      closed = true;
      await localSub.cancel();
      await channel.unsubscribe();
      await controller.close();
    };
    return controller.stream;
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

    if (!SupabaseInit.isOnlineMode) {
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

    await _db.from('messages').insert({
      'author_id': uid,
      'author_name': name,
      'body': storedText,
      'type': 'text',
      'pinned': false,
      'reactions': <String, int>{},
      'flagged': flagged,
      'flag_reason': reason,
      'group_id': groupId,
      'is_anonymous': anonymous,
    });
    // Refresh the feed right away: without this the sent message only
    // appears when a Realtime event arrives (and never, if Realtime is
    // off for the messages table — the "chat issue", 2026-11-23).
    _notifyLocalChange();
  }

  Future<void> sendPhoto(
    String localPath, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    if (!SupabaseInit.isOnlineMode) {
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
    await _db.from('messages').insert({
      'author_id': uid,
      'author_name': name,
      'photo_url': url,
      'type': 'photo',
      'pinned': false,
      'reactions': <String, int>{},
      'flagged': false,
      'group_id': groupId,
      'is_anonymous': anonymous,
    });
    _notifyLocalChange();
  }

  Future<void> sendVoice(
    String localPath,
    int seconds, {
    String? groupId,
    bool anonymous = false,
  }) async {
    final (uid, name) = await _author();
    if (!SupabaseInit.isOnlineMode) {
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
    await _db.from('messages').insert({
      'author_id': uid,
      'author_name': name,
      'voice_url': url,
      'body': 'Voice message ($seconds s)',
      'type': 'voice',
      'pinned': false,
      'reactions': <String, int>{},
      'flagged': false,
      'group_id': groupId,
      'is_anonymous': anonymous,
    });
    _notifyLocalChange();
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
    if (!SupabaseInit.isOnlineMode) {
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
    final messageRow = await _db
        .from('messages')
        .insert({
          'author_id': uid,
          'author_name': name,
          'type': 'poll',
          'pinned': false,
          'reactions': <String, int>{},
          'flagged': false,
          'group_id': groupId,
          'is_anonymous': anonymous,
        })
        .select('id')
        .single();
    final messageId = (messageRow['id'] as Object?)?.toString();
    if (messageId == null) return;
    final pollRow = await _db
        .from('polls')
        .insert({
          'message_id': messageId,
          'question': question,
          'options': options,
          'votes': <String, int>{},
        })
        .select('id')
        .single();
    final pollId = (pollRow['id'] as Object?)?.toString();
    if (pollId != null) {
      await _db
          .from('messages')
          .update({'poll_id': pollId})
          .eq('id', messageId);
    }
    _notifyLocalChange();
  }

  // -- interactions -----------------------------------------------------

  /// One vote per user: the `polls` row's `votes` map is updated with
  /// votes[currentUid] = optionIndex, overwriting any previous vote.
  Future<void> vote(String messageId, int optionIndex) async {
    final uid = AuthService.instance.effectiveUid;
    if (uid == null || !SupabaseInit.isOnlineMode) return;
    try {
      final pollRow = await _db
          .from('polls')
          .select('id, votes')
          .eq('message_id', messageId)
          .maybeSingle();
      if (pollRow == null) return;
      final votes = Map<String, dynamic>.from(pollRow['votes'] as Map? ?? {});
      votes[uid] = optionIndex;
      await _db
          .from('polls')
          .update({'votes': votes})
          .eq('id', pollRow['id']);
      _notifyLocalChange();
    } catch (_) {
      // Best effort; the stream re-emits the stored votes on next load.
    }
  }

  /// Toggles [uid]'s reaction for [emoji] inside a stored `reactions`
  /// map and returns the new map. Pure, so it is unit-tested.
  ///
  /// New shape: `reactions[emoji]` is the list of reactor uids, so the
  /// count is the list length and a second tap removes the user again.
  /// Legacy shape: a bare int count (no owners) migrates to `[uid]` on
  /// the first toggle — the old anonymous count cannot be attributed
  /// to anyone, so it restarts from this user.
  static Map<String, dynamic> toggleReactionIn(
    Map<String, dynamic> raw,
    String emoji,
    String uid,
  ) {
    final next = Map<String, dynamic>.from(raw);
    final current = next[emoji];
    final List<String> users;
    if (current is List) {
      users = current.map((e) => e.toString()).toList();
    } else {
      users = <String>[];
    }
    if (users.contains(uid)) {
      users.remove(uid);
    } else {
      users.add(uid);
    }
    next[emoji] = users;
    return next;
  }

  /// Toggles the current user's reaction for [emoji] on [messageId]:
  /// first tap adds it, second tap removes it again. One user can
  /// only ever hold one reaction per emoji.
  Future<void> react(String messageId, String emoji) async {
    final uid = AuthService.instance.effectiveUid;
    if (uid == null || !SupabaseInit.isOnlineMode) return;
    try {
      final row = await _db
          .from('messages')
          .select('reactions')
          .eq('id', messageId)
          .maybeSingle();
      if (row == null) return;
      final reactions =
          Map<String, dynamic>.from(row['reactions'] as Map? ?? {});
      await _db.from('messages').update(
        {'reactions': toggleReactionIn(reactions, emoji, uid)},
      ).eq('id', messageId);
      // Refresh the feed right away, like the other writes: without
      // this the count only moves when a Realtime event arrives.
      _notifyLocalChange();
    } catch (_) {
      // Best effort.
    }
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
    if (!SupabaseInit.isOnlineMode) {
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
    await _db.from('messages').insert({
      'author_id': uid,
      'author_name': name,
      'is_anonymous': anonymous,
      'body': storedText,
      'type': 'text',
      'reply_to': messageId,
      'reply_to_text': replyToText,
      'pinned': false,
      'reactions': <String, int>{},
      'flagged': flagged,
      'flag_reason': flagged ? Moderation.flagReason(text) : null,
    });
  }

  Future<void> togglePin(String messageId, bool pinned) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db
          .from('messages')
          .update({'pinned': pinned})
          .eq('id', messageId);
    } catch (_) {
      // Best effort.
    }
  }

  /// Toggles the local bookmark for this message (bookmarks are
  /// local-only — see the class doc). The feed stream re-emits so the
  /// screens' bookmark filter updates.
  Future<void> toggleBookmark(String messageId) async {
    // No uid needed: bookmarks are local-only (per device), so they
    // work with no login at all.
    await _loadBookmarks();
    if (_bookmarkedIds.contains(messageId)) {
      _bookmarkedIds.remove(messageId);
    } else {
      _bookmarkedIds.add(messageId);
    }
    await _persistBookmarks();
    _notifyLocalChange();
  }

  Future<void> report(String messageId, String reason) async {
    final uid = AuthService.instance.effectiveUid;
    if (!SupabaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'report',
        'messageId': messageId,
        'reason': reason,
        'reporterUid': uid,
      });
      return;
    }
    await _db.from('reports').insert({
      'message_id': messageId,
      'reporter_id': uid,
      'reason': reason,
    });
    await _db.from('messages').update({
      'flagged': true,
      'flag_reason': reason,
    }).eq('id', messageId);
    _notifyLocalChange();
  }

  Future<void> blockUser(String uid) async {
    final myUid = AuthService.instance.effectiveUid;
    if (myUid == null) return;
    if (!SupabaseInit.isOnlineMode) {
      await _enqueue({
        'type': 'block',
        'uid': myUid,
        'targetUid': uid,
      });
      return;
    }
    try {
      final row = await _db
          .from('users')
          .select('blocked_ids')
          .eq('id', myUid)
          .maybeSingle();
      final blocked =
          (row?['blocked_ids'] as List?)?.map((e) => e.toString()).toList() ??
              [];
      if (!blocked.contains(uid)) blocked.add(uid);
      await _db.from('users').update({
        'blocked_ids': blocked,
      }).eq('id', myUid);
    } catch (_) {
      // Best effort.
    }
  }
}
