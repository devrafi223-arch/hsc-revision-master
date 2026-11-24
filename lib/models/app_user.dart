/// A user account, from the custom backend's `users` table (id = the
/// JWT uid).
///
/// [toMap] emits the snake_case column names (`display_name`,
/// `photo_url`, `is_admin`, `chapters_done`, ...). [fromMap] accepts
/// those names plus the old camelCase names, so cached / legacy maps
/// still parse.
///
/// This is the signed-in user's own account only — there is no
/// community left in the app, so there is no following list and no
/// profile/photo privacy here.
class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    this.coverUrl,
    this.isAdmin = false,
    this.streak = 0,
    this.totalChaptersDone = 0,
    this.lastSeenAt,
    List<String>? milestoneIds,
  }) : milestoneIds = milestoneIds ?? [];

  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final String? coverUrl;

  /// Backend column: `is_admin`.
  final bool isAdmin;
  final int streak;

  /// Backend column: `chapters_done`.
  final int totalChaptersDone;

  /// Backend column: `last_seen_at` (ISO string). Used by the admin
  /// panel's "Active today" count.
  final DateTime? lastSeenAt;
  final List<String> milestoneIds;

  Map<String, dynamic> toMap() => {
        'display_name': name,
        'email': email,
        'photo_url': photoUrl,
        'cover_url': coverUrl,
        'is_admin': isAdmin,
        'streak': streak,
        'chapters_done': totalChaptersDone,
        'milestone_ids': milestoneIds,
      };

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: (m['display_name'] as String?) ??
            (m['name'] as String?) ??
            '',
        email: (m['email'] as String?) ?? '',
        photoUrl: (m['photo_url'] as String?) ?? (m['photoUrl'] as String?),
        coverUrl: (m['cover_url'] as String?) ?? (m['coverUrl'] as String?),
        isAdmin: (m['is_admin'] == true) || (m['isAdmin'] == true),
        streak: (m['streak'] as num?)?.toInt() ?? 0,
        totalChaptersDone: (m['chapters_done'] as num?)?.toInt() ??
            (m['totalChaptersDone'] as num?)?.toInt() ??
            0,
        milestoneIds: (m['milestone_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            (m['milestoneIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        lastSeenAt: DateTime.tryParse(
          (m['last_seen_at'] as String?) ??
              (m['lastSeenAt'] as String?) ??
              '',
        ),
      );
}
