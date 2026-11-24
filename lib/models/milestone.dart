/// A milestone earned by finishing a chapter fully. One milestone per
/// subject + chapter — the display name comes from [Milestones.nameFor].
/// Mirrored to the custom backend's `milestones` table (POST
/// /api/milestones, one row per user + chapter).
class Milestone {
  Milestone({
    required this.id,
    required this.name,
    required this.subject,
    required this.chapterTitle,
    required this.earnedAt,
  });

  final String id;
  final String name;
  final String subject;
  final String chapterTitle;
  final DateTime earnedAt;

  Map<String, dynamic> toMap() => {
        'name': name,
        'subject': subject,
        'chapterTitle': chapterTitle,
        // Epoch millis: JSON-safe (offline queue) and parses back
        // through fromMap.
        'earnedAt': earnedAt.millisecondsSinceEpoch,
      };

  /// Accepts both the app map shape ([toMap]) and a raw backend row
  /// (`unlocked_at` ISO string, `chapter_id` instead of `chapterTitle`).
  factory Milestone.fromMap(String id, Map<String, dynamic> m) {
    final raw = m['unlocked_at'] ?? m['earnedAt'];
    final DateTime earnedAt;
    if (raw is num) {
      earnedAt = DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true)
          .toLocal();
    } else if (raw is String) {
      earnedAt = DateTime.tryParse(raw) ?? DateTime.now();
    } else {
      earnedAt = DateTime.now();
    }
    return Milestone(
      id: id,
      name: (m['name'] as String?) ?? '',
      subject: (m['subject'] as String?) ?? '',
      chapterTitle: (m['chapterTitle'] as String?) ??
          (m['chapter_id'] as String?) ??
          '',
      earnedAt: earnedAt,
    );
  }
}
