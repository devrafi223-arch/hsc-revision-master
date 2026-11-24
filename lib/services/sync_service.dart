import 'dart:async';

import 'auth_service.dart';
import 'connectivity_service.dart';
import 'notes_repository.dart';
import 'offline_queue.dart';

/// Offline → online sync.
///
/// Listens to [ConnectivityService.connectivityStream]; when the device
/// comes back online it drains the [OfflineQueue] (SharedPreferences
/// key 'offline-queue-v1') and replays the queued ops against the
/// custom backend.
///
/// Replay is implemented for op type 'note' only (per-chapter notes
/// saved while offline → NotesRepository.saveNote). Any other op type
/// is dropped: the community message/report ops belonged to the
/// removed community feature and can never replay.
///
/// [isOfflineStream] emits true while the device is offline, for the UI
/// offline indicator.
class SyncService {
  SyncService._() {
    _subscription = ConnectivityService.connectivityStream.listen((online) {
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
  Stream<bool> get onlineStream => ConnectivityService.connectivityStream;

  /// Emits true while the device is offline (for the UI indicator).
  Stream<bool> get isOfflineStream =>
      ConnectivityService.connectivityStream.map((online) => !online);

  /// Drains the offline queue now. Safe to call while offline (no-op
  /// when there is no connection or no signed-in user — queued writes
  /// need a JWT) and safe to call concurrently (a second call while a
  /// sync is running returns immediately).
  Future<void> syncNow() async {
    if (_syncing) return;
    if (!await ConnectivityService.isConnected) return;
    if (!AuthService.instance.isSignedIn) return;
    _syncing = true;
    try {
      final queue = await OfflineQueue.loadQueue();
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
      await OfflineQueue.persistQueue(remaining);
    } finally {
      _syncing = false;
    }
  }

  /// Replays one queued op. Returns true when the op is done;
  /// returns false to keep the op queued for a later sync. Unknown
  /// op types are dropped (they belong to the removed community
  /// feature and can never replay, so keeping them would loop
  /// forever).
  Future<bool> _replay(Map<String, dynamic> op) async {
    final type = op['type'] as String?;
    switch (type) {
      case 'note':
        await NotesRepository.instance.saveNote(
          chapterId: (op['chapterId'] as String?) ?? '',
          text: (op['text'] as String?) ?? '',
          localPhotoPath: op['localPhotoPath'] as String?,
        );
        return true;
      default:
        return true;
    }
  }
}
