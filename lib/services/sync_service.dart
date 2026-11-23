import 'dart:async';

import 'community_service.dart';
import 'firebase_init.dart';
import 'notes_repository.dart';
import 'offline_queue.dart';

/// Offline → online sync.
///
/// Listens to [FirebaseInit.connectivityStream]; when the device comes
/// back online it drains the [OfflineQueue] (SharedPreferences key
/// 'offline-queue-v1') and replays the queued ops.
///
/// Replay is implemented for op types 'message' and 'note' only:
///   - 'message' → CommunityService (text / photo / voice / poll).
///     The 'flaggedOriginal' field is stripped before replay — it lives
///     only in the local queue and is never uploaded.
///   - 'note' → NotesRepository.saveNote.
/// Other op types (e.g. 'report', 'block') are left in the queue for a
/// later sync; replaying them is a TODO.
///
/// [isOfflineStream] emits true while the device is offline, for the UI
/// offline indicator.
class SyncService {
  SyncService._() {
    _subscription = FirebaseInit.connectivityStream.listen((online) {
      if (online) {
        unawaited(syncNow());
      }
    });
  }

  static final SyncService instance = SyncService._();

  StreamSubscription<bool>? _subscription;
  bool _syncing = false;

  /// Cancels the connectivity listener (only needed in tests; the
  /// singleton lives for the whole app lifetime).
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Emits the online state (true = online).
  Stream<bool> get onlineStream => FirebaseInit.connectivityStream;

  /// Emits true while the device is offline (for the UI indicator).
  Stream<bool> get isOfflineStream =>
      FirebaseInit.connectivityStream.map((online) => !online);

  /// Drains the offline queue now. Safe to call while offline (no-op
  /// when there is no connection) and safe to call concurrently (a second
  /// call while a sync is running returns immediately).
  Future<void> syncNow() async {
    if (_syncing) return;
    if (!FirebaseInit.isOnlineMode) return;
    if (!await FirebaseInit.isConnected) return;
    _syncing = true;
    try {
      final queue = await CommunityService.loadQueue();
      if (queue.isEmpty) return;
      final remaining = OfflineQueue();
      for (final op in queue.pending) {
        var done = false;
        try {
          done = await _replay(op);
        } catch (_) {
          done = false;
        }
        if (!done) remaining.enqueue(op);
      }
      await CommunityService.persistQueue(remaining);
    } finally {
      _syncing = false;
    }
  }

  /// Replays one queued op. Returns true when the op is done (an unknown
  /// *message kind* inside a 'message' op is dropped so it cannot loop
  /// forever); returns false to keep the op queued for a later sync.
  /// Unknown *op types* (e.g. 'report', 'block') are kept, not dropped —
  /// see the class comment.
  Future<bool> _replay(Map<String, dynamic> op) async {
    final type = op['type'] as String?;
    switch (type) {
      case 'message':
        // 'flaggedOriginal' is local-only: never uploaded.
        final messageType = op['messageType'] as String? ?? 'text';
        final groupId = op['groupId'] as String?;
        switch (messageType) {
          case 'text':
            await CommunityService.instance.sendText(
              (op['text'] as String?) ?? '',
              groupId: groupId,
            );
          case 'photo':
            final localPath = op['localPath'] as String?;
            if (localPath == null) return true;
            await CommunityService.instance.sendPhoto(
              localPath,
              groupId: groupId,
            );
          case 'voice':
            final localPath = op['localPath'] as String?;
            if (localPath == null) return true;
            await CommunityService.instance.sendVoice(
              localPath,
              (op['seconds'] as num?)?.toInt() ?? 0,
              groupId: groupId,
            );
          case 'poll':
            final poll = op['poll'];
            if (poll is! Map) return true;
            final pollMap = poll.cast<String, dynamic>();
            await CommunityService.instance.sendPoll(
              (pollMap['question'] as String?) ?? '',
              (pollMap['options'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [],
              groupId: groupId,
            );
          default:
            return true; // Unknown message kind — drop, don't loop forever.
        }
        return true;
      case 'note':
        await NotesRepository.instance.saveNote(
          chapterId: (op['chapterId'] as String?) ?? '',
          text: (op['text'] as String?) ?? '',
          localPhotoPath: op['localPhotoPath'] as String?,
        );
        return true;
      default:
        // TODO: replay 'report' / 'block' ops. Kept in the queue so the
        // action is not silently lost.
        return false;
    }
  }
}
