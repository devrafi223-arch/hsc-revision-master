import 'api_client.dart';
import 'auth_service.dart';

/// Server-side chapter completion (leaderboard + `chapters_done`).
///
/// Best effort, never throws: the local tracker is the source of
/// truth — the celebration and the local milestone already happened
/// before this is called. A re-post of the same chapter is a server
/// no-op (UNIQUE user + chapter) and does not double-count.
class ProgressService {
  static Future<void> recordChapterDone({
    required String chapterId,
    required String subject,
  }) async {
    if (!AuthService.instance.isSignedIn) return;
    try {
      await ApiClient.instance.post(
        '/api/milestones',
        auth: true,
        body: {'chapter_id': chapterId, 'subject': subject},
      );
    } catch (_) {
      // Best effort; the local milestone already happened.
    }
  }
}
