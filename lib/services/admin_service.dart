import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_init.dart';

/// Admin panel backend. Firestore collections: `users`, `messages`,
/// `reports`.
///
/// Who is an admin?
///   1. The Firestore user doc has `isAdmin == true`, OR
///   2. (LOCAL FALLBACK) the uid matches the first user ever registered on
///      this device, stored in SharedPreferences under 'first-user-uid'.
///      The first user to register on a fresh install becomes the admin
///      until a real `isAdmin` flag is set in Firestore — Rafi should set
///      `isAdmin: true` on his own user doc in the Firebase console and
///      then this fallback no longer matters.
///
/// All counts are best effort; everything returns 0 / empty in local mode
/// and never throws.
class AdminService {
  AdminService._();

  static final AdminService instance = AdminService._();

  /// Records [uid] as the first registered user on this device, if none
  /// is recorded yet. Called by the registration flow (see AuthService).
  static Future<void> recordFirstUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('first-user-uid') == null) {
      await prefs.setString('first-user-uid', uid);
    }
  }

  Future<bool> isAdmin(String uid) async {
    if (FirebaseInit.isOnlineMode) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.data()?['isAdmin'] == true) return true;
      } catch (_) {
        // Fall through to the local fallback below.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('first-user-uid') == uid;
  }

  /// Keys: totalUsers, totalMessages, totalReports, activeToday.
  /// activeToday is best effort (users whose doc has an `lastSeenAt`
  /// timestamp within the last 24h; 0 when that field is absent).
  Future<Map<String, int>> stats() async {
    if (!FirebaseInit.isOnlineMode) {
      return {
        'totalUsers': 0,
        'totalMessages': 0,
        'totalReports': 0,
        'activeToday': 0,
      };
    }
    final db = FirebaseFirestore.instance;
    var totalUsers = 0;
    var totalMessages = 0;
    var totalReports = 0;
    var activeToday = 0;
    try {
      totalUsers = (await db.collection('users').count().get()).count ?? 0;
    } catch (_) {}
    try {
      totalMessages =
          (await db.collection('messages').count().get()).count ?? 0;
    } catch (_) {}
    try {
      totalReports =
          (await db.collection('reports').count().get()).count ?? 0;
    } catch (_) {}
    try {
      final since =
          DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
      activeToday = (await db
              .collection('users')
              .where('lastSeenAt', isGreaterThanOrEqualTo: since)
              .count()
              .get())
          .count ??
          0;
    } catch (_) {}
    return {
      'totalUsers': totalUsers,
      'totalMessages': totalMessages,
      'totalReports': totalReports,
      'activeToday': activeToday,
    };
  }

  /// Newest reports first. Offline → an empty list.
  Stream<List<Map<String, dynamic>>> reportsStream() {
    if (!FirebaseInit.isOnlineMode) return Stream.value([]);
    return FirebaseFirestore.instance
        .collection('reports')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              return {...doc.data(), 'id': doc.id};
            }).toList());
  }

  /// Prevents the user from posting (the app checks `muted == true`).
  /// Offline → no-op (admin actions need Firestore).
  Future<void> muteUser(String uid) async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'muted': true});
    } catch (_) {
      // Best effort.
    }
  }

  /// Blocks the user from the app entirely (`banned == true`).
  /// Offline → no-op (admin actions need Firestore).
  Future<void> banUser(String uid) async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'banned': true});
    } catch (_) {
      // Best effort.
    }
  }

  /// Deletes a community message. Offline → no-op (admin actions need
  /// Firestore).
  Future<void> deleteMessage(String messageId) async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (_) {
      // Best effort.
    }
  }
}
