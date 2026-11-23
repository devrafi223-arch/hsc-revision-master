/// PC foreground-app detection for desktop Focus Mode.
///
/// Implementations live behind [createDesktopBlocker] (see
/// desktop_blocker.dart): Windows via Win32 FFI, Linux via
/// wmctrl/xdotool, and a no-op stub on web / in tests. The watcher
/// ([DesktopWatcher] in desktop_watcher.dart) polls [foregroundExe]
/// while a focus session or a scheduled block is active.
///
/// Honest limits: this is best-effort desktop blocking. The app runs
/// as a normal user process, so Task Manager can always close it, and
/// on Linux/Wayland window listing is restricted — Linux support is
/// labelled "best effort" in the UI.
abstract class DesktopBlocker {
  /// True on Windows / Linux with the needed tools present.
  bool get isSupported;

  /// False when the platform is right but the tools are missing
  /// (e.g. no wmctrl/xdotool on Linux).
  bool get isAvailable;

  /// Human-readable reason when [isAvailable] is false.
  String get unavailableReason;

  /// Lowercase basename of the foreground app's executable
  /// (e.g. `chrome.exe`, `code`), or null when it cannot be read.
  Future<String?> foregroundExe();

  /// Bring this app's own window to the front.
  Future<void> bringAppToFront();

  /// Politely ask the foreground window to close (WM_CLOSE /
  /// `xdotool windowclose`). Returns true when the request was sent.
  Future<bool> closeForegroundWindow();
}
