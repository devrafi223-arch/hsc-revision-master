import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_init.dart';

/// Who is online in the community right now (Supabase Realtime
/// Presence — the "active" state). The snapshot is the single source
/// the community screen listens to; it never throws.
class PresenceSnapshot {
  const PresenceSnapshot({
    this.onlineUids = const {},
    this.typingNames = const [],
  });

  /// Uids currently tracked on the presence channel (includes self).
  final Set<String> onlineUids;

  /// Display names of OTHER users who are typing right now.
  final List<String> typingNames;

  /// Pure parse of a Realtime presence state, so it is unit-tested
  /// without a socket. Each presence payload carries `uid`, `name`
  /// and `typing`.
  static PresenceSnapshot fromStates(
    List<SinglePresenceState> states,
    String selfUid,
  ) {
    final online = <String>{};
    final typing = <String>[];
    for (final state in states) {
      for (final presence in state.presences) {
        final uid = presence.payload['uid']?.toString();
        if (uid == null || uid.isEmpty) continue;
        online.add(uid);
        if (uid != selfUid && presence.payload['typing'] == true) {
          final name =
              presence.payload['name']?.toString() ?? 'Someone';
          if (name.isNotEmpty && !typing.contains(name)) {
            typing.add(name);
          }
        }
      }
    }
    return PresenceSnapshot(onlineUids: online, typingNames: typing);
  }
}

/// Tracks this device on the `community-presence` Realtime channel
/// and exposes who else is online / typing.
///
/// Fail-soft by design: presence rides the same Realtime socket as
/// the message feed. If the socket is unreachable (offline, or the
/// project host is blocked on this network) the snapshot simply stays
/// empty — the feed and the rest of the app keep working.
class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  /// The current snapshot; the community screen listens to this.
  final ValueNotifier<PresenceSnapshot> notifier =
      ValueNotifier(const PresenceSnapshot());

  RealtimeChannel? _channel;
  String? _uid;
  String _name = 'Student';
  bool _typing = false;
  Timer? _typingTimer;

  bool get isActive => _channel != null;

  /// Joins the presence channel as [uid] ([name] is shown in the
  /// "X is typing…" line). No-op while offline or already joined.
  Future<void> start({required String uid, required String name}) async {
    if (_channel != null) return;
    if (!SupabaseInit.isOnlineMode) return;
    _uid = uid;
    _name = name.isEmpty ? 'Student' : name;
    try {
      final channel = SupabaseInit.client.channel('community-presence');
      channel.onPresenceSync((_) => _refresh());
      channel.subscribe();
      _channel = channel;
      await channel.track(_payload(false));
    } catch (_) {
      // Presence is best effort; never break the screen.
      _channel = null;
    }
  }

  Map<String, dynamic> _payload(bool typing) => {
        'uid': _uid,
        'name': _name,
        'typing': typing,
      };

  void _refresh() {
    final channel = _channel;
    if (channel == null) return;
    try {
      notifier.value =
          PresenceSnapshot.fromStates(channel.presenceState(), _uid ?? '');
    } catch (_) {
      // Keep the last snapshot on a parse failure.
    }
  }

  /// Call on every composer keystroke. Marks this user typing and
  /// clears it again 3 seconds after the last keystroke.
  void setTyping() {
    if (_channel == null || _uid == null) return;
    if (!_typing) {
      _typing = true;
      _track();
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      _typing = false;
      _track();
    });
  }

  /// Call when a message is sent: typing ends at once.
  void clearTyping() {
    _typingTimer?.cancel();
    if (_typing) {
      _typing = false;
      _track();
    }
  }

  void _track() {
    try {
      _channel?.track(_payload(_typing));
    } catch (_) {
      // Best effort.
    }
  }

  /// Leaves the channel and resets the snapshot.
  Future<void> stop() async {
    _typingTimer?.cancel();
    _typing = false;
    final channel = _channel;
    _channel = null;
    _uid = null;
    if (channel != null) {
      try {
        await channel.untrack();
      } catch (_) {}
      try {
        await SupabaseInit.client.removeChannel(channel);
      } catch (_) {}
    }
    notifier.value = const PresenceSnapshot();
  }
}
