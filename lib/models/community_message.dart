import 'package:cloud_firestore/cloud_firestore.dart';

/// The kind of a community message.
enum MessageType { text, photo, poll, voice }

/// A poll attached to a community message. One vote per user, enforced by
/// the [votes] map key: userId -> optionIndex. Re-voting overwrites the
/// previous vote instead of adding a second one (same as Telegram).
class PollData {
  PollData({
    required this.id,
    required this.question,
    required this.options,
    Map<String, int>? votes,
  }) : votes = votes ?? {};

  final String id;
  final String question;
  final List<String> options;

  /// userId -> optionIndex.
  final Map<String, int> votes;

  /// Vote count per option, in the same order as [options].
  List<int> get counts {
    final result = List<int>.filled(options.length, 0);
    for (final index in votes.values) {
      if (index >= 0 && index < result.length) result[index]++;
    }
    return result;
  }

  /// Vote share per option as a percentage (0-100). All 0 when no votes.
  List<double> get percentages {
    final total = votes.length;
    if (total == 0) return List<double>.filled(options.length, 0);
    return counts.map((c) => c * 100 / total).toList();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'question': question,
        'options': options,
        'votes': votes,
      };

  factory PollData.fromMap(Map<String, dynamic> m) {
    final rawVotes = m['votes'];
    final votes = <String, int>{};
    if (rawVotes is Map) {
      for (final entry in rawVotes.entries) {
        votes[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return PollData(
      id: (m['id'] as String?) ?? '',
      question: (m['question'] as String?) ?? '',
      options: (m['options'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      votes: votes,
    );
  }
}

/// One message in the universal community (or inside a group when
/// [groupId] is set). Stored in Firestore collection `messages`.
///
/// When [isAnonymous] is true the UI shows "Anonymous" with no name or
/// photo, but [authorId] is still stored, so moderation, reporting and
/// blocking still apply.
class CommunityMessage {
  CommunityMessage({
    required this.id,
    required this.authorId,
    required this.authorName,
    this.authorPhoto,
    this.text,
    this.photoUrl,
    this.voiceUrl,
    this.replyToId,
    this.replyToText,
    required this.type,
    required this.timestamp,
    this.poll,
    this.pinned = false,
    Map<String, int>? reactions,
    List<String>? bookmarkedBy,
    this.flagged = false,
    this.flagReason,
    this.groupId,
    this.isAnonymous = false,
  })  : reactions = reactions ?? {},
        bookmarkedBy = bookmarkedBy ?? [];

  final String id;
  final String authorId;
  final String authorName;
  final String? authorPhoto;
  final String? text;
  final String? photoUrl;
  final String? voiceUrl;
  final String? replyToId;
  final String? replyToText;
  final MessageType type;
  final DateTime timestamp;
  final PollData? poll;
  final bool pinned;

  /// emoji -> count.
  final Map<String, int> reactions;

  /// Uids of users who bookmarked this message.
  final List<String> bookmarkedBy;

  final bool flagged;
  final String? flagReason;

  /// null = universal community, otherwise the group id.
  final String? groupId;

  /// When true the UI shows "Anonymous" with no name or photo. The
  /// [authorId] is still stored, so moderation, reporting and blocking
  /// still apply.
  final bool isAnonymous;

  Map<String, dynamic> toMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'authorPhoto': authorPhoto,
        'text': text,
        'photoUrl': photoUrl,
        'voiceUrl': voiceUrl,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'type': type.name,
        // Stored as epoch millis so the same map is JSON-safe (offline
        // queue) and Firestore-safe.
        'timestamp': timestamp.millisecondsSinceEpoch,
        'poll': poll?.toMap(),
        'pinned': pinned,
        'reactions': reactions,
        'bookmarkedBy': bookmarkedBy,
        'flagged': flagged,
        'flagReason': flagReason,
        'groupId': groupId,
        'isAnonymous': isAnonymous,
      };

  factory CommunityMessage.fromMap(String id, Map<String, dynamic> m) {
    final rawTs = m['timestamp'];
    final DateTime timestamp;
    if (rawTs is Timestamp) {
      timestamp = rawTs.toDate();
    } else if (rawTs is num) {
      timestamp =
          DateTime.fromMillisecondsSinceEpoch(rawTs.toInt(), isUtc: true)
              .toLocal();
    } else if (rawTs is String) {
      timestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }
    final rawReactions = m['reactions'];
    final reactions = <String, int>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        reactions[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    final rawType = (m['type'] as String?) ?? 'text';
    return CommunityMessage(
      id: id,
      authorId: (m['authorId'] as String?) ?? '',
      authorName: (m['authorName'] as String?) ?? '',
      authorPhoto: m['authorPhoto'] as String?,
      text: m['text'] as String?,
      photoUrl: m['photoUrl'] as String?,
      voiceUrl: m['voiceUrl'] as String?,
      replyToId: m['replyToId'] as String?,
      replyToText: m['replyToText'] as String?,
      type: MessageType.values.firstWhere(
        (t) => t.name == rawType,
        orElse: () => MessageType.text,
      ),
      timestamp: timestamp,
      poll: m['poll'] is Map<String, dynamic>
          ? PollData.fromMap(m['poll'] as Map<String, dynamic>)
          : m['poll'] is Map
              ? PollData.fromMap(
                  (m['poll'] as Map).cast<String, dynamic>(),
                )
              : null,
      pinned: m['pinned'] == true,
      reactions: reactions,
      bookmarkedBy: (m['bookmarkedBy'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      flagged: m['flagged'] == true,
      flagReason: m['flagReason'] as String?,
      groupId: m['groupId'] as String?,
      isAnonymous: m['isAnonymous'] == true,
    );
  }
}
