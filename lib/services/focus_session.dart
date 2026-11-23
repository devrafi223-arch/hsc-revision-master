import '../focus_schedule.dart';
import '../focus_store.dart';
import 'focus_channel.dart';

/// The one shared implementation of starting / ending a focus session,
/// used by the Focus tab and by the HomeScreen schedule ticker, so the
/// Dart store and the native Android service can never disagree.
///
/// Starting writes the session to the store AND pushes the full rule
/// set (whitelist, locked flag, schedule, caps, dismiss-until) to the
/// native service. Ending a session early while the schedule is active
/// also records a dismiss-until at the end of the current blocked run,
/// so neither the service nor the ticker instantly restarts it.
class FocusSession {
  static Future<void> start({
    required FocusStore store,
    required FocusSchedule schedule,
    required FocusChannel channel,
    required DateTime end,
    int? minutes,
    String? chapterId,
    bool auto = false,
  }) async {
    await store.startUntil(
      end,
      minutes: minutes,
      chapterId: chapterId,
      auto: auto,
    );
    await channel.startFocus(
      whitelist: store.whitelist.toList(),
      endEpochMs: end.millisecondsSinceEpoch,
      locked: store.locked,
      scheduleJson: schedule.toJsonString(),
      capsJson: store.capsJson,
      dismissedUntilMs:
          store.scheduleDismissedUntil?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// User-initiated end. Returns false when a locked session is still
  /// running — it cannot be stopped early. Timer expiry must use
  /// [FocusStore.end] directly, never this.
  static Future<bool> end({
    required FocusStore store,
    required FocusSchedule schedule,
    required FocusChannel channel,
  }) async {
    if (!store.canEnd) return false;
    final now = DateTime.now();
    if (schedule.isBlockedAt(now)) {
      // Ending early during a scheduled block: don't let it restart.
      final blockEnd = schedule.activeBlockEnd(now);
      if (blockEnd != null) {
        await store.dismissScheduleUntil(blockEnd);
      }
    }
    await store.end();
    await channel.syncBlocking(
      scheduleJson: schedule.toJsonString(),
      locked: store.locked,
      capsJson: store.capsJson,
      dismissedUntilMs:
          store.scheduleDismissedUntil?.millisecondsSinceEpoch ?? 0,
    );
    await channel.stopFocus();
    return true;
  }

  /// Push the current rules to the native service (call after the
  /// schedule, locked flag or caps change, without starting a session).
  static Future<void> sync({
    required FocusStore store,
    required FocusSchedule schedule,
    required FocusChannel channel,
  }) async {
    await channel.syncBlocking(
      scheduleJson: schedule.toJsonString(),
      locked: store.locked,
      capsJson: store.capsJson,
      dismissedUntilMs:
          store.scheduleDismissedUntil?.millisecondsSinceEpoch ?? 0,
    );
  }
}
