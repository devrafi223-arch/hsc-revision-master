import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Push / reminders + in-app milestone notifications.
///
/// The custom backend has NO push: there is no server push in this app.
/// Push is a LOCAL-REMINDER STUB instead:
///   * [notifyMilestone] pushes the milestone name onto
///     [milestoneNotifications], which the UI listens to and shows as a
///     local in-app notification (banner/confetti — the UI agent owns
///     the display).
///   * [scheduleDailyReminder] stores the chosen morning reminder time
///     locally; [notifyDailyReminder] surfaces a revision reminder on
///     [dailyReminders], which the UI shows in-app.
///
/// TODO: real push to OTHER devices (a daily revision reminder, a daily
/// motivation quote, or a friend's milestone) needs a Vercel cron /
/// Edge Function + FCM server key for real push. A push cannot be sent
/// from the app itself without exposing the server key, so this service
/// deliberately does NOT fake a server send.
class MessagingService {
  static final StreamController<String> _milestoneController =
      StreamController<String>.broadcast();

  /// In-app milestone notifications (milestone names). The UI listens.
  static Stream<String> get milestoneNotifications =>
      _milestoneController.stream;

  static final StreamController<String> _reminderController =
      StreamController<String>.broadcast();

  /// In-app daily revision reminders (reminder text). The UI listens.
  static Stream<String> get dailyReminders => _reminderController.stream;

  /// SharedPreferences key for the locally stored reminder time.
  static const String reminderTimeKey = 'daily-reminder-time-v1';

  /// No-op setup. Never throws. There is no FCM token to fetch — see
  /// the class doc: real push needs a server (Vercel cron + FCM key).
  static Future<void> init() async {
    // Nothing to register: the custom backend has no client push SDK.
  }

  /// Announces a newly earned milestone inside the app.
  static Future<void> notifyMilestone(String milestoneName) async {
    if (!_milestoneController.isClosed) {
      _milestoneController.add(milestoneName);
    }
  }

  /// Stores the daily revision reminder time (hour/minute) on this device.
  /// This only records the preference — actually firing at that time needs
  /// a Vercel cron / Edge Function + FCM server key for real push (see
  /// class doc); until then the UI can call [notifyDailyReminder] itself,
  /// e.g. when the app is opened in the morning.
  static Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      reminderTimeKey,
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    );
  }

  /// Returns the stored daily reminder time as 'HH:MM', or null when the
  /// user never set one.
  static Future<String?> get dailyReminderTime async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(reminderTimeKey);
  }

  /// Surfaces a revision reminder inside the app (in-app only — not a
  /// system push notification).
  static Future<void> notifyDailyReminder([String? text]) async {
    if (!_reminderController.isClosed) {
      _reminderController.add(
        text ?? 'Time for revision — knock out today\'s chapters!',
      );
    }
  }
}
