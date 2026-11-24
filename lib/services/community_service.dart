import 'dart:async';

import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community_message.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'moderation.dart';
import 'offline_queue.dart';

/// Universal community feed, backed by the custom backend (REST).
///
/// Reading: [messagesStream] polls GET /api/messages?since= every
/// 2.5 s (no WebSocket on Vercel serverless — see backend/README.md)
/// and does a full refresh every 30 s, so reactions, pins and flags
/// on old messages arrive too. Polls are joined from GET /api/polls
/// on every tick.
///
/// Writing needs a JWT: the server sets the author name from the
/// signed-in user. A write with no/invalid token throws
/// `ApiException(UNAUTHORIZED)` — the caller shows "please log in"
/// (the app root signs the user out on a 401). A write that fails
/// with NETWORK is enqueued into [OfflineQueue] and replayed by
/// [SyncService] when the device is back online.
///
/// Moderation: [Moderation.isFlagged] runs on every text message. A
/// flagged message is stored with its text replaced by
/// 'Removed by moderation'; the original text is kept ONLY in the
/// local offline queue under 'flaggedOriginal' and is never uploaded.
///
/// Photos: the backend has no photo column, so a photo message is
/// stored as a message whose text IS the Blob image URL (uploaded
/// first via POST /api/upload?kind=note). [CommunityMessage.fromMap]
/// renders that back as a photo.
///
/// Voice messages are gone: recording was a UI stub and the backend
/// has no audio storage. The composer mic button shows "coming soon".
///
/// Anonymous posting is gone too: the backend always records the JWT
/// user's name — every message shows its author.
///
/// Blocking is LOCAL-ONLY now (no backend endpoint): blocked author
/// ids live in SharedPreferences under 'blocked-users-v1' and their
/// messages are filtered out of the feed on this device.
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

  /// SharedPreferences key holding the locally blocked author ids.
  static const String blockedKey = 'blocked-users-v1';

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

  // -- local blocks -------------------------------------------------------

  Set<String> _blockedIds = {};
  bool _blockedLoaded = false;

  Future<void> _loadBlocked() async {
    if (_blockedLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _blockedIds = (prefs.getStringList(blockedKey) ?? []).toSet();
    } catch (_) {
      _blockedIds = {};
    }
    _blockedLoaded = true;
  }

  Future<void> _persistBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(blockedKey, _blockedIds.toList());
    } catch (_) {
      // Best effort; the in-memory set is kept.
    }
  }

  // -- polling state ------------------------------------------------------

  static const _pollInterval = Duration(milliseconds: 2500);
  static const _fullRefreshInterval = Duration(seconds: 30);

  List<CommunityMessage> _cached = [];
  String? _newestCreatedAt;
  DateTime _lastFullFetch = DateTime.fromMillisecondsSinceEpoch(0);

  void _forceFullRefresh() {
    _lastFullFetch = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Fetches the current polls once (joined onto messages by poll_id).
  Future<Map<String, PollData>> _fetchPolls() async {
    final byId = <String, PollData>{};
    try {
      final res = await ApiClient.instance.get(
        '/api/polls',
        query: {'limit': '50'},
      );
      for (final row in (res['polls'] as List?) ?? []) {
        if (row is Map) {
          final map = row.cast<String, dynamic>();
          final id = (map['id'] as String?) ?? '';
          if (id.isNotEmpty) byId[id] = PollData.fromMap(map);
        }
      }
    } catch (_) {
      // Polls are best effort; messages still show without them.
    }
    return byId;
  }

  List<CommunityMessage> _parseMessages(
    List<dynamic> rows,
    Map<String, PollData> pollsById,
  ) {
    final messages = <CommunityMessage>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final map = row.cast<String, dynamic>();
      final pollId = map['poll_id'] as String?;
      if (pollId != null && pollsById.containsKey(pollId)) {
        map['poll'] = pollsById[pollId]!.toMap();
      }
      messages.add(
        CommunityMessage.fromMap((map['id'] as String?) ?? '', map),
      );
    }
    return messages;
  }

  /// Full fetch: the latest 100 messages, oldest first. Resets the
  /// cache, the newest-created_at watermark and the full-fetch clock.
  Future<List<CommunityMessage>> _fetchAll() async {
    await _loadBookmarks();
    await _loadBlocked();
    final pollsById = await _fetchPolls();
    final res = await ApiClient.instance.get(
      '/api/messages',
      query: {'limit': '100'},
    );
    final rows = (res['messages'] as List?) ?? [];
    _cached = _parseMessages(rows, pollsById);
    if (rows.isNotEmpty) {
      final last = rows.last;
      if (last is Map) {
        _newestCreatedAt = (last['created_at'] as String?) ?? _newestCreatedAt;
      }
    }
    _lastFullFetch = DateTime.now();
    return _applyLocalState(_cached);
  }

  /// Incremental fetch: only messages newer than [_newestCreatedAt].
  /// Merges them into the cache (by id) and returns the merged list.
  Future<List<CommunityMessage>> _fetchSince() async {
    final since = _newestCreatedAt;
    if (since == null) return _fetchAll();
    final pollsById = await _fetchPolls();
    final res = await ApiClient.instance.get(
      '/api/messages',
      query: {'since': since, 'limit': '100'},
    );
    final rows = (res['messages'] as List?) ?? [];
    if (rows.isEmpty) return _applyLocalState(_cached);
    final fresh = _parseMessages(rows, pollsById);
    final byId = {for (final m in _cached) m.id: m};
    for (final m in fresh) {
      byId[m.id] = m;
    }
    _cached = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final last = rows.last;
    if (last is Map) {
      _newestCreatedAt = (last['created_at'] as String?) ?? _newestCreatedAt;
    }
    return _applyLocalState(_cached);
  }

  /// One poll tick: full refresh when due (or on first load),
  /// incremental fetch otherwise.
  Future<List<CommunityMessage>> _pollOnce() async {
    if (_cached.isEmpty ||
        DateTime.now().difference(_lastFullFetch) > _fullRefreshInterval) {
      return _fetchAll();
    }
    return _fetchSince();
  }

  /// Merges the local bookmark set into [messages] and drops messages
  /// from locally blocked authors.
  List<CommunityMessage> _applyLocalState(List<CommunityMessage> messages) {
    final uid = AuthService.instance.currentUid;
    return messages.where((m) => !_blockedIds.contains(m.authorId)).map(
      (m) {
        if (uid == null || !_bookmarkedIds.contains(m.id)) return m;
        return CommunityMessage(
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
          reactionUsers: m.reactionUsers,
          bookmarkedBy: [uid],
          flagged: m.flagged,
          flagReason: m.flagReason,
          groupId: m.groupId,
        );
      },
    ).toList();
  }

  // -- reading ----------------------------------------------------------

  /// Oldest first (chronological — newest at the bottom). The stream
  /// polls the backend every 2.5 s; a failed tick keeps the last list
  /// and retries on the next tick. Offline on first load → an empty
  /// list (queued messages live in the offline queue until they sync).
  Stream<List<CommunityMessage>> messagesStream() {
    final controller = StreamController<List<CommunityMessage>>();
    var closed = false;
    Timer? timer;
    Future<void> emit() async {
      try {
        final messages = await _pollOnce();
        if (!closed) controller.add(messages);
      } catch (_) {
        // Keep the stream alive; the next tick retries. On first load
        // with nothing cached, emit empty so the UI stops spinning.
        if (!closed && _cached.isEmpty) controller.add([]);
      }
    }

    unawaited(emit());
    timer = Timer.periodic(_pollInterval, (_) => unawaited(emit()));
    final localSub = _localChanges.stream.listen((_) => unawaited(emit()));
    controller.onCancel = () async {
      closed = true;
      timer?.cancel();
      await localSub.cancel();
      await controller.close();
    };
    return controller.stream;
  }

  // -- sending ----------------------------------------------------------

  /// Posts one text message. NETWORK failure → queued for SyncService;
  /// UNAUTHORIZED → the session is dead (signs out, rethrows).
  Future<void> _postText(
    String text, {
    String? replyToId,
    String? replyToText,
    String? pollId,
  }) async {
    final flagged = Moderation.isFlagged(text);
    final reason = flagged ? Moderation.flagReason(text) : null;
    final storedText = flagged ? 'Removed by moderation' : text;
    try {
      await ApiClient.instance.post(
        '/api/messages',
        auth: true,
        body: {
          'text': storedText,
          if (replyToId != null) 'reply_to_id': replyToId,
          if (replyToText != null) 'reply_to_text': replyToText,
          if (pollId != null) 'poll_id': pollId,
        },
      );
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        final op = <String, dynamic>{
          'type': 'message',
          'messageType': 'text',
          'text': storedText,
          'flagged': flagged,
          'flagReason': reason,
          if (replyToId != null) 'replyToId': replyToId,
          if (replyToText != null) 'replyToText': replyToText,
          if (pollId != null) 'pollId': pollId,
        };
        // Original text lives ONLY in the local queue, never uploaded.
        if (flagged) op['flaggedOriginal'] = text;
        await enqueueOp(op);
        return;
      }
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
    // Refresh the feed right away: without this the sent message only
    // appears on the next 2.5 s tick.
    _notifyLocalChange();
  }

  Future<void> sendText(String text) async {
    await _postText(text);
  }

  /// Uploads a photo to Blob, then posts a message whose text IS the
  /// image URL (see the class doc). NETWORK failure → queued.
  Future<void> sendPhoto(String localPath) async {
    final bytes = await XFile(localPath).readAsBytes();
    final name =
        'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    late final String url;
    try {
      final res = await ApiClient.instance.uploadImage(
        filename: name,
        kind: 'note',
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      url = (res['url'] as String?) ?? '';
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        await enqueueOp({
          'type': 'message',
          'messageType': 'photo',
          'localPath': localPath,
        });
        return;
      }
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
    if (url.isEmpty) {
      throw ApiException('SERVER_ERROR', 'Photo upload failed.');
    }
    await _postText(url);
  }

  /// Creates the poll, then posts a message linking it (the message
  /// text is the question). The poll card is joined client-side from
  /// GET /api/polls.
  Future<void> sendPoll(String question, List<String> options) async {
    late final String pollId;
    try {
      final res = await ApiClient.instance.post(
        '/api/polls',
        auth: true,
        body: {'question': question, 'options': options},
      );
      final poll = res['poll'] as Map?;
      pollId = (poll?['id'] as String?) ?? '';
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        await enqueueOp({
          'type': 'message',
          'messageType': 'poll',
          'poll': {
            'question': question,
            'options': options,
          },
        });
        return;
      }
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
    if (pollId.isEmpty) {
      throw ApiException('SERVER_ERROR', 'Could not create the poll.');
    }
    await _postText(question, pollId: pollId);
  }

  // -- interactions -----------------------------------------------------

  /// One vote per user: the backend removes the user from every other
  /// option first, so a re-vote moves the vote instead of doubling it.
  /// [pollId] is the poll's id (not the message id).
  Future<void> vote(String pollId, int optionIndex) async {
    if (pollId.isEmpty) return;
    try {
      await ApiClient.instance.post(
        '/api/polls/$pollId/vote',
        auth: true,
        body: {'option_index': optionIndex},
      );
      _forceFullRefresh();
      _notifyLocalChange();
    } on ApiException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
  }

  /// Toggles [uid]'s reaction for [emoji] inside a stored `reactions`
  /// map and returns the new map. Pure, so it is unit-tested. Used for
  /// the optimistic update in [react]; the server is the source of
  /// truth (POST /api/messages/:id/react toggles server-side too).
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
    final uid = AuthService.instance.currentUid;
    if (uid == null) {
      throw ApiException('UNAUTHORIZED', 'Please log in to continue.');
    }
    // Optimistic: flip it in the cache now, the server confirms it
    // on the next full refresh.
    final index = _cached.indexWhere((m) => m.id == messageId);
    CommunityMessage? optimistic;
    if (index != -1) {
      final m = _cached[index];
      final reactions = toggleReactionIn(
        {for (final e in m.reactionUsers.entries) e.key: e.value},
        emoji,
        uid,
      );
      final users = <String, List<String>>{};
      final counts = <String, int>{};
      for (final e in reactions.entries) {
        if (e.value is List) {
          final list = (e.value as List).map((v) => v.toString()).toList();
          users[e.key] = list;
          counts[e.key] = list.length;
        }
      }
      optimistic = CommunityMessage(
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
        reactions: counts,
        reactionUsers: users,
        bookmarkedBy: m.bookmarkedBy,
        flagged: m.flagged,
        flagReason: m.flagReason,
        groupId: m.groupId,
      );
      _cached[index] = optimistic;
      _notifyLocalChange();
    }
    try {
      await ApiClient.instance.post(
        '/api/messages/$messageId/react',
        auth: true,
        body: {'emoji': emoji},
      );
      _forceFullRefresh();
      _notifyLocalChange();
    } on ApiException catch (e) {
      // Roll the optimistic flip back on failure.
      if (index != -1 && optimistic != null) {
        _forceFullRefresh();
        _notifyLocalChange();
      }
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
  }

  Future<void> reply(
    String messageId,
    String text,
    String replyToText,
  ) async {
    await _postText(
      text,
      replyToId: messageId,
      replyToText: replyToText,
    );
  }

  /// Pins/unpins a message. Admin only — the server enforces it and
  /// answers 403 for everyone else.
  Future<void> togglePin(String messageId, bool pinned) async {
    try {
      await ApiClient.instance.post(
        '/api/messages/$messageId/pin',
        auth: true,
        body: {'pinned': pinned},
      );
      _forceFullRefresh();
      _notifyLocalChange();
    } on ApiException catch (e) {
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
  }

  /// Toggles the local bookmark for this message (bookmarks are
  /// local-only — see the class doc). The feed stream re-emits so the
  /// screens' bookmark filter updates.
  Future<void> toggleBookmark(String messageId) async {
    // Bookmarks are local-only (per device); the community tab itself
    // requires login, so a uid is always present here.
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
    try {
      await ApiClient.instance.post(
        '/api/messages/$messageId/report',
        auth: true,
        body: {'reason': reason},
      );
      _forceFullRefresh();
      _notifyLocalChange();
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        await enqueueOp({
          'type': 'report',
          'messageId': messageId,
          'reason': reason,
        });
        return;
      }
      if (e.code == 'UNAUTHORIZED') {
        await AuthService.instance.signOut();
      }
      rethrow;
    }
  }

  /// Blocks a user LOCALLY (no backend endpoint): their messages stop
  /// showing in the feed on this device. The feed re-emits at once.
  Future<void> blockUser(String uid) async {
    await _loadBlocked();
    _blockedIds.add(uid);
    await _persistBlocked();
    _notifyLocalChange();
  }
}
