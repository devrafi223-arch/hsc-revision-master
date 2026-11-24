/// The kind of a community message.
enum MessageType { text, photo, poll, voice }

/// A poll attached to a community message. One vote per user, enforced by
/// the [votes] map key: userId -> optionIndex. Re-voting overwrites the
/// previous vote instead of adding a second one (same as Telegram).
///
/// [fromMap] accepts both shapes: the client shape `{uid: optionIndex}`
/// (what [toMap] writes) and the backend shape `{optionIndex: [uid, ...]}`
/// (what GET /api/polls returns) — the backend shape is inverted here.
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
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          // Backend shape: {optionIndex: [uid, ...]} — invert it so
          // one user still holds exactly one option index.
          final index = int.tryParse(key) ?? -1;
          if (index >= 0) {
            for (final uid in value) {
              votes[uid.toString()] = index;
            }
          }
        } else {
          votes[key] = (value as num?)?.toInt() ?? 0;
        }
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

/// One message in the universal community. Stored in the custom
/// backend's `messages` table (no group chats: the backend has no
/// group_id column).
///
/// A photo message is stored as a message whose [text] IS the Blob
/// image URL — the backend has no photo column, so [fromMap] detects
/// a lone image URL and exposes it as [photoUrl] with [text] null.
///
/// There is no anonymous posting: the backend always records the JWT
/// user's name, and every message shows its author.
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
    Map<String, List<String>>? reactionUsers,
    List<String>? bookmarkedBy,
    this.flagged = false,
    this.flagReason,
    this.groupId,
  })  : reactions = reactions ?? {},
        reactionUsers = reactionUsers ?? {},
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

  /// emoji -> uids who reacted (new shape, one entry per user, so a
  /// tap toggles instead of adding forever). Legacy rows store an int
  /// count here with no owners; those show the count until the first
  /// toggle, which migrates the emoji to this shape.
  final Map<String, List<String>> reactionUsers;

  /// Uids of users who bookmarked this message.
  final List<String> bookmarkedBy;

  final bool flagged;
  final String? flagReason;

  /// null = universal community, otherwise the group id.
  final String? groupId;

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
        // queue) and parses back through fromMap.
        'timestamp': timestamp.millisecondsSinceEpoch,
        'poll': poll?.toMap(),
        'pinned': pinned,
        'reactions': reactions,
        'reactionUsers': reactionUsers,
        'bookmarkedBy': bookmarkedBy,
        'flagged': flagged,
        'flagReason': flagReason,
        'groupId': groupId,
      };

  /// Accepts both the app/offline-queue map shape ([toMap]: `text`,
  /// `timestamp` as epoch millis, `type`, camelCase keys) and a raw
  /// backend row (snake_case: `text`, `created_at` ISO string,
  /// `author_id`, `is_pinned`, `is_flagged`, `poll_id`). When `type`
  /// is absent (backend rows) it is derived from which media/poll
  /// field is set — including a lone image URL as `text`, which is
  /// how photo messages are stored (see the class doc).
  ///
  /// True when [text] is a lone image URL (the photo-message encoding).
  static bool isImageUrl(String text) {
    final t = text.trim();
    if (!t.startsWith('http')) return false;
    if (t.contains(' ')) return false;
    final path = t.split('?').first.toLowerCase();
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp');
  }

  factory CommunityMessage.fromMap(String id, Map<String, dynamic> m) {
    final rawTs = m['created_at'] ?? m['timestamp'];
    final DateTime timestamp;
    if (rawTs is num) {
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
    final reactionUsers = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          // New shape: the list IS the owners, so the count is its
          // length and a tap can toggle this user.
          final users = value.map((e) => e.toString()).toList();
          reactions[key] = users.length;
          reactionUsers[key] = users;
        } else {
          // Legacy shape: a bare int count with no owners.
          reactions[key] = (value as num?)?.toInt() ?? 0;
        }
      }
    }
    // Offline-queue round-trip: toMap writes reactionUsers separately.
    final rawUsers = m['reactionUsers'];
    if (rawUsers is Map) {
      for (final entry in rawUsers.entries) {
        final key = entry.key.toString();
        if (entry.value is List) {
          final users = (entry.value as List).map((e) => e.toString()).toList();
          reactionUsers[key] = users;
          reactions[key] = users.length;
        }
      }
    }
    // Photo-message encoding: the message text IS the Blob image URL.
    final rawText = (m['body'] as String?) ?? (m['text'] as String?);
    final textIsPhoto = rawText != null && isImageUrl(rawText);
    final photoUrl = textIsPhoto
        ? rawText
        : (m['photo_url'] as String?) ?? (m['photoUrl'] as String?);
    final hasPoll = m['poll'] is Map || m['poll_id'] != null;
    final hasPhoto = photoUrl?.isNotEmpty == true;
    final hasVoice =
        (m['voice_url'] as String?)?.isNotEmpty == true ||
            (m['voiceUrl'] as String?)?.isNotEmpty == true;
    final rawType = (m['type'] as String?) ??
        (hasPoll
            ? 'poll'
            : hasPhoto
                ? 'photo'
                : hasVoice
                    ? 'voice'
                    : 'text');
    return CommunityMessage(
      id: id,
      authorId: (m['author_id'] as String?) ?? (m['authorId'] as String?) ?? '',
      authorName:
          (m['author_name'] as String?) ?? (m['authorName'] as String?) ?? '',
      authorPhoto:
          (m['author_photo'] as String?) ?? (m['authorPhoto'] as String?),
      text: textIsPhoto ? null : rawText,
      photoUrl: photoUrl,
      voiceUrl: (m['voice_url'] as String?) ?? (m['voiceUrl'] as String?),
      replyToId: (m['reply_to'] as String?) ?? (m['replyToId'] as String?),
      replyToText:
          (m['reply_to_text'] as String?) ?? (m['replyToText'] as String?),
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
      pinned: m['pinned'] == true || m['is_pinned'] == true,
      reactions: reactions,
      reactionUsers: reactionUsers,
      bookmarkedBy: (m['bookmarkedBy'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (m['bookmarked_by'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      flagged: m['flagged'] == true || m['is_flagged'] == true,
      flagReason:
          (m['flag_reason'] as String?) ?? (m['flagReason'] as String?),
      groupId: (m['group_id'] as String?) ?? (m['groupId'] as String?),
    );
  }
}
