/// A user profile, stored in the Supabase `users` table (id = Auth uid).
///
/// [toMap] emits the Supabase snake_case column names
/// (`display_name`, `photo_url`, `privacy`, `photo_privacy`, `is_admin`,
/// `chapters_done`, ...). [fromMap] accepts both those names and the old
/// Firestore camelCase names, so cached / legacy maps still parse.
class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    this.coverUrl,
    this.profileVisibility = 'public',
    this.photoVisibility = 'all',
    this.isAdmin = false,
    this.streak = 0,
    this.totalChaptersDone = 0,
    List<String>? milestoneIds,
    List<String>? followingIds,
  })  : milestoneIds = milestoneIds ?? [],
        followingIds = followingIds ?? [];

  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final String? coverUrl;

  /// 'public' | 'restricted' | 'locked'. Default 'public'.
  /// Supabase column: `privacy`.
  final String profileVisibility;

  /// 'all' | 'onlyMe'. Default 'all'.
  /// Supabase column: `photo_privacy`.
  final String photoVisibility;

  /// Supabase column: `is_admin`.
  final bool isAdmin;
  final int streak;

  /// Supabase column: `chapters_done`.
  final int totalChaptersDone;
  final List<String> milestoneIds;
  final List<String> followingIds;

  Map<String, dynamic> toMap() => {
        'display_name': name,
        'email': email,
        'photo_url': photoUrl,
        'cover_url': coverUrl,
        'privacy': profileVisibility,
        'photo_privacy': photoVisibility,
        'is_admin': isAdmin,
        'streak': streak,
        'chapters_done': totalChaptersDone,
        'milestone_ids': milestoneIds,
        'following_ids': followingIds,
      };

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: (m['display_name'] as String?) ??
            (m['name'] as String?) ??
            '',
        email: (m['email'] as String?) ?? '',
        photoUrl: (m['photo_url'] as String?) ?? (m['photoUrl'] as String?),
        coverUrl: (m['cover_url'] as String?) ?? (m['coverUrl'] as String?),
        profileVisibility: (m['privacy'] as String?) ??
            (m['profileVisibility'] as String?) ??
            'public',
        photoVisibility: (m['photo_privacy'] as String?) ??
            (m['photoVisibility'] as String?) ??
            'all',
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
        followingIds: (m['following_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            (m['followingIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}
