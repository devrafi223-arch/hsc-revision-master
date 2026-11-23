import 'package:cloud_firestore/cloud_firestore.dart';

/// A milestone earned by finishing a chapter fully. One milestone per
/// subject + chapter — the display name comes from [Milestones.nameFor].
/// Stored in Firestore collection `milestones` (doc id = milestone id).
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
        // Epoch millis: JSON-safe (offline queue) and Firestore-safe.
        'earnedAt': earnedAt.millisecondsSinceEpoch,
      };

  factory Milestone.fromMap(String id, Map<String, dynamic> m) {
    final raw = m['earnedAt'];
    final DateTime earnedAt;
    if (raw is Timestamp) {
      earnedAt = raw.toDate();
    } else if (raw is num) {
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
      chapterTitle: (m['chapterTitle'] as String?) ?? '',
      earnedAt: earnedAt,
    );
  }
}
