import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_init.dart';

/// Firebase Cloud Messaging setup + in-app milestone notifications.
///
/// [init] is fully guarded (try/catch, no-op without config) and never
/// throws. [notifyMilestone] pushes the milestone name onto
/// [milestoneNotifications], which the UI listens to and shows as a local
/// in-app notification (banner/confetti — the UI agent owns the display).
///
/// TODO: sending an FCM push to OTHER devices (e.g. a daily motivation
/// quote or a friend's milestone) needs a server — FCM topic/device sends
/// cannot be done from the app itself without exposing the server key.
/// That is a backend / Cloud Function job; this service deliberately does
/// NOT fake a server send.
class MessagingService {
  static final StreamController<String> _milestoneController =
      StreamController<String>.broadcast();

  /// In-app milestone notifications (milestone names). The UI listens.
  static Stream<String> get milestoneNotifications =>
      _milestoneController.stream;

  /// Requests notification permission and fetches the FCM token.
  /// No-op (returns immediately) when Firebase is not configured.
  static Future<void> init() async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      // Token is fetched best-effort so the backend can target this device
      // later; failure here must never break startup.
      await messaging.getToken();
      FirebaseMessaging.onMessage.listen((_) {
        // Foreground FCM messages arrive here. The UI agent owns any
        // foreground display; nothing is done automatically.
      });
    } catch (_) {
      // FCM unavailable (no config, no Play services, web without a
      // service worker, ...) — the app keeps working without pushes.
    }
  }

  /// Announces a newly earned milestone inside the app. If FCM is
  /// configured, a best-effort topic send to other devices is a TODO
  /// (needs a server — see the class doc comment).
  static Future<void> notifyMilestone(String milestoneName) async {
    if (!_milestoneController.isClosed) {
      _milestoneController.add(milestoneName);
    }
  }
}
