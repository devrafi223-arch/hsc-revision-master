/// Voice messages in the community chat.
///
/// STUB — no real recording or playback yet, on purpose.
///
/// Real recording/playback needs the `record` + `just_audio` packages,
/// which were NOT added to pubspec.yaml for this update (to keep the build
/// light and avoid new native permissions until Rafi confirms voice is
/// wanted in the next build). Until those packages are added:
///   - [startRecording] returns null,
///   - [stopRecording] returns null,
///   - [playVoice]/[stopPlaying] do nothing.
///
/// The UI treats a null result as "voice recording coming soon" and shows
/// a friendly message — a recording is NEVER faked.
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  /// Starts recording. Returns null: recording is not implemented yet
  /// (needs the `record` package — see the file doc comment).
  Future<String?> startRecording() async {
    return null;
  }

  /// Stops recording. Returns null: recording is not implemented yet
  /// (needs the `record` package). When implemented this returns
  /// `{'path': ..., 'seconds': ...}`.
  Future<Map<String, dynamic>?> stopRecording() async {
    return null;
  }

  /// Plays a voice message from a local path or URL. No-op until the
  /// `just_audio` package is added (see the file doc comment).
  Future<void> playVoice(String pathOrUrl) async {}

  /// Stops any voice playback. No-op until `just_audio` is added.
  Future<void> stopPlaying() async {}
}
