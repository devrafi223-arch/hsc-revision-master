import '../models/app_user.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Admin panel backend (web `/admin` route only — there is no admin
/// entry in the app UI).
///
/// Who is an admin? ONLY a user whose `/api/auth/me` row has
/// `is_admin == true`. There is deliberately NO local/device
/// fallback: the admin signs in with email + 6-digit code, the JWT
/// carries the flag, and the server re-checks it on every admin call.
///
/// What the backend offers (see backend/README.md):
/// - GET /api/admin/users (paginated, newest first)
/// - DELETE /api/admin/users?id= (never self)
///
/// What does NOT exist (no endpoints): message/report counts, a
/// reports stream, mute, ban, delete-message. [stats] therefore
/// reports only what the users list can prove: Total users (from the
/// paginated `total`) and Active today (users whose `last_seen_at`
/// is within the last 24 h). totalMessages / totalReports stay 0.
class AdminService {
  AdminService._();

  static final AdminService instance = AdminService._();

  /// Strict admin check: the signed-in user's row must have
  /// `is_admin == true` (from GET /api/auth/me). No local fallback.
  bool isAdmin() => AuthService.instance.currentUser?.isAdmin == true;

  /// One page of users, newest first. Returns
  /// `{'total': int, 'users': [AppUser, ...]}`. Throws [ApiException]
  /// (FORBIDDEN when the caller is not an admin, NETWORK when
  /// offline).
  Future<Map<String, dynamic>> listUsers({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await ApiClient.instance.get(
      '/api/admin/users',
      auth: true,
      query: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final rows = (res['users'] as List?) ?? [];
    final users = rows
        .whereType<Map>()
        .map((row) {
          final map = row.cast<String, dynamic>();
          return AppUser.fromMap((map['id'] as String?) ?? '', map);
        })
        .where((u) => u.id.isNotEmpty)
        .toList();
    return {
      'total': (res['total'] as num?)?.toInt() ?? users.length,
      'users': users,
    };
  }

  /// Keys: totalUsers, activeToday, totalMessages (0), totalReports
  /// (0 — see the class doc). Computed from the users list fetch.
  Future<Map<String, int>> stats() async {
    try {
      final page = await listUsers(limit: 100);
      final users = page['users'] as List<AppUser>;
      final since = DateTime.now().subtract(const Duration(hours: 24));
      var activeToday = 0;
      for (final u in users) {
        if (u.lastSeenAt != null && u.lastSeenAt!.isAfter(since)) {
          activeToday++;
        }
      }
      return {
        'totalUsers': (page['total'] as int?) ?? users.length,
        'totalMessages': 0,
        'totalReports': 0,
        'activeToday': activeToday,
      };
    } catch (_) {
      return {
        'totalUsers': 0,
        'totalMessages': 0,
        'totalReports': 0,
        'activeToday': 0,
      };
    }
  }

  /// Deletes a user server-side. Never self — the server enforces it
  /// and answers 400. Throws [ApiException] on failure.
  Future<void> deleteUser(String id) async {
    await ApiClient.instance.delete('/api/admin/users', query: {'id': id});
  }
}
