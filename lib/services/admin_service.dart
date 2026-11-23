import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_init.dart';

/// Admin panel backend. Supabase tables: `users`, `messages`, `reports`.
///
/// Who is an admin?
///   1. The Supabase user row has `is_admin == true`, OR
///   2. (LOCAL FALLBACK) the uid matches the first user ever registered on
///      this device, stored in SharedPreferences under 'first-user-uid'.
///      The first user to register on a fresh install becomes the admin
///      until a real `is_admin` flag is set in Supabase — Rafi should set
///      `is_admin: true` on his own user row in the Supabase dashboard and
///      then this fallback no longer matters.
///
/// All counts are best effort; everything returns 0 / empty in local mode
/// and never throws.
class AdminService {
  AdminService._();

  static final AdminService instance = AdminService._();

  SupabaseClient get _db => SupabaseInit.client;

  /// Records [uid] as the first registered user on this device, if none
  /// is recorded yet. Called by the registration flow (see AuthService).
  static Future<void> recordFirstUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('first-user-uid') == null) {
      await prefs.setString('first-user-uid', uid);
    }
  }

  Future<bool> isAdmin(String uid) async {
    if (SupabaseInit.isOnlineMode) {
      try {
        final row = await _db
            .from('users')
            .select('is_admin')
            .eq('id', uid)
            .maybeSingle();
        if (row?['is_admin'] == true) return true;
      } catch (_) {
        // Fall through to the local fallback below.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('first-user-uid') == uid;
  }

  /// Counts one table exactly (best effort, 0 on any error).
  Future<int> _count(String table) async {
    try {
      final response =
          await _db.from(table).select().count(CountOption.exact);
      return response.count;
    } catch (_) {
      return 0;
    }
  }

  /// Keys: totalUsers, totalMessages, totalReports, activeToday.
  /// activeToday is best effort (users whose row has a `last_seen_at`
  /// timestamp within the last 24h; 0 when that field is absent).
  Future<Map<String, int>> stats() async {
    if (!SupabaseInit.isOnlineMode) {
      return {
        'totalUsers': 0,
        'totalMessages': 0,
        'totalReports': 0,
        'activeToday': 0,
      };
    }
    final totalUsers = await _count('users');
    final totalMessages = await _count('messages');
    final totalReports = await _count('reports');
    var activeToday = 0;
    try {
      final since =
          DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
      final response = await _db
          .from('users')
          .select()
          .gte('last_seen_at', since)
          .count(CountOption.exact);
      activeToday = response.count;
    } catch (_) {
      // Best effort.
    }
    return {
      'totalUsers': totalUsers,
      'totalMessages': totalMessages,
      'totalReports': totalReports,
      'activeToday': activeToday,
    };
  }

  /// Newest reports first. Offline → an empty list.
  Stream<List<Map<String, dynamic>>> reportsStream() {
    if (!SupabaseInit.isOnlineMode) return Stream.value([]);
    final controller = StreamController<List<Map<String, dynamic>>>();
    var closed = false;
    Future<void> emit() async {
      try {
        final rows = await _db
            .from('reports')
            .select()
            .order('created_at', ascending: false)
            .limit(100);
        if (closed) return;
        controller.add(
          (rows as List).whereType<Map>().map((row) {
            final map = row.cast<String, dynamic>();
            return {...map, 'id': (map['id'] as Object?)?.toString()};
          }).toList(),
        );
      } catch (_) {
        // Keep the stream alive; the next Realtime event retries.
      }
    }

    unawaited(emit());
    final channel = _db
        .channel('public:reports')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (_) => unawaited(emit()),
        )
        .subscribe();
    controller.onCancel = () async {
      closed = true;
      await channel.unsubscribe();
      await controller.close();
    };
    return controller.stream;
  }

  /// Prevents the user from posting (the app checks `is_muted == true`).
  /// Offline → no-op (admin actions need Supabase).
  Future<void> muteUser(String uid) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db.from('users').update({'is_muted': true}).eq('id', uid);
    } catch (_) {
      // Best effort.
    }
  }

  /// Blocks the user from the app entirely (`is_banned == true`).
  /// Offline → no-op (admin actions need Supabase).
  Future<void> banUser(String uid) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db.from('users').update({'is_banned': true}).eq('id', uid);
    } catch (_) {
      // Best effort.
    }
  }

  /// Deletes a community message (and its poll row, if any).
  /// Offline → no-op (admin actions need Supabase).
  Future<void> deleteMessage(String messageId) async {
    if (!SupabaseInit.isOnlineMode) return;
    try {
      await _db.from('polls').delete().eq('message_id', messageId);
    } catch (_) {
      // Best effort; the message delete below is the important part.
    }
    try {
      await _db.from('messages').delete().eq('id', messageId);
    } catch (_) {
      // Best effort.
    }
  }
}
