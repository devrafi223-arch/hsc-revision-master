/// Keyword moderation for community messages. Pure Dart — no Firebase.
///
/// Any message containing a blocked word (case-insensitive substring match)
/// is auto-flagged: it is stored with flagged=true and its text replaced by
/// 'Removed by moderation' (see CommunityService).
class Moderation {
  static const List<String> blockedWords = [
    'porn',
    'sex',
    'xxx',
    '18+',
    'nude',
    'casino',
    'betting',
    'spam',
    'free money',
    'crypto giveaway',
  ];

  /// True when [text] contains any blocked word (case-insensitive).
  static bool isFlagged(String text) => flagReason(text) != null;

  /// The reason for flagging, naming the first blocked word found,
  /// or null when the text is clean.
  static String? flagReason(String text) {
    final lower = text.toLowerCase();
    for (final word in blockedWords) {
      if (lower.contains(word)) {
        return 'Contains blocked word: $word';
      }
    }
    return null;
  }
}
