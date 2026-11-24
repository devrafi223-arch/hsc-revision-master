import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Who is online in the community right now.
///
/// Polling, not Realtime: Vercel serverless has no WebSocket, so the
/// client heartbeats POST /api/presence every 30 s (which stamps the
/// user's `last_seen_at`) and polls GET /api/presence every 10 s for
/// the users seen in the last 5 minutes. The snapshot is the single
/// source the community screen listens to; it never throws.
///
/// Typing was dropped with the backend move: there is no typing
/// column to write to, and a serverless function cannot push a
/// "typing…" event. Online dots stay; the typing line is gone.
class PresenceSnapshot {
  const PresenceSnapshot({this.onlineUids = const {}});

  /// Uids seen in the last 5 minutes (includes self).
  final Set<String> onlineUids;

  /// Pure parse of the GET /api/presence rows, so it is unit-tested
  /// without a network call. Each row carries `id` (+ display name
  /// and `last_seen_at`, which the dots do not need).
  static PresenceSnapshot fromApi(List<dynamic> rows) {
    final online = <String>{};
    for (final row in rows) {
      if (row is Map) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) online.add(id);
      }
    }
    return PresenceSnapshot(onlineUids: online);
  }
}

/// Heartbeats + polls presence while the community screen is open.
///
/// Fail-soft by design: a failed heartbeat or poll is swallowed and
/// the snapshot simply stays as it was — the feed and the rest of the
/// app keep working.
class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  /// The current snapshot; the community screen listens to this.
  final ValueNotifier<PresenceSnapshot> notifier =
      ValueNotifier(const PresenceSnapshot());

  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  bool _active = false;

  bool get isActive => _active;

  /// Starts heartbeating + polling. No-op when already started.
  /// Only heartbeats while signed in (POST /api/presence needs a
  /// JWT); the online list itself is public.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    await _beat();
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_beat()));
    _pollTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_refresh()));
    await _refresh();
  }

  Future<void> _beat() async {
    if (!AuthService.instance.isSignedIn) return;
    try {
      await ApiClient.instance.post('/api/presence', auth: true);
    } catch (_) {
      // Best effort; the next heartbeat retries.
    }
  }

  Future<void> _refresh() async {
    try {
      final res = await ApiClient.instance.get('/api/presence');
      final rows = (res['online'] as List?) ?? [];
      notifier.value = PresenceSnapshot.fromApi(rows);
    } catch (_) {
      // Keep the last snapshot on any failure.
    }
  }

  /// Stops both timers and resets the snapshot.
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _heartbeatTimer = null;
    _pollTimer = null;
    _active = false;
    notifier.value = const PresenceSnapshot();
  }
}
