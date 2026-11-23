import 'desktop_blocker_base.dart';

/// No-op desktop blocker for web builds and tests.
DesktopBlocker createDesktopBlocker() => _StubBlocker();

class _StubBlocker implements DesktopBlocker {
  @override
  bool get isSupported => false;

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason =>
      'PC blocking works on Windows and Linux only.';

  @override
  Future<String?> foregroundExe() async => null;

  @override
  Future<void> bringAppToFront() async {}

  @override
  Future<bool> closeForegroundWindow() async => false;
}
