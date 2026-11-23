/// A user profile, stored in Firestore collection `users` (doc id = uid).
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
  final String profileVisibility;

  /// 'all' | 'onlyMe'. Default 'all'.
  final String photoVisibility;

  final bool isAdmin;
  final int streak;
  final int totalChaptersDone;
  final List<String> milestoneIds;
  final List<String> followingIds;

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'coverUrl': coverUrl,
        'profileVisibility': profileVisibility,
        'photoVisibility': photoVisibility,
        'isAdmin': isAdmin,
        'streak': streak,
        'totalChaptersDone': totalChaptersDone,
        'milestoneIds': milestoneIds,
        'followingIds': followingIds,
      };

  factory AppUser.fromMap(String id, Map<String, dynamic> m) => AppUser(
        id: id,
        name: (m['name'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        photoUrl: m['photoUrl'] as String?,
        coverUrl: m['coverUrl'] as String?,
        profileVisibility: (m['profileVisibility'] as String?) ?? 'public',
        photoVisibility: (m['photoVisibility'] as String?) ?? 'all',
        isAdmin: m['isAdmin'] == true,
        streak: (m['streak'] as num?)?.toInt() ?? 0,
        totalChaptersDone: (m['totalChaptersDone'] as num?)?.toInt() ?? 0,
        milestoneIds: (m['milestoneIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        followingIds: (m['followingIds'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}
