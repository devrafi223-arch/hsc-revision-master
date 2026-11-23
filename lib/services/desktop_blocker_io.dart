import 'dart:io';

import 'desktop_blocker_base.dart';
import 'desktop_blocker_linux.dart';
import 'desktop_blocker_stub.dart' as stub;
import 'desktop_blocker_windows.dart';

/// Picks the desktop blocker for the current OS. In a flutter_test
/// run (FLUTTER_TEST=true) the stub is returned, so tests never spawn
/// real processes or touch Win32.
DesktopBlocker createDesktopBlocker() {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return stub.createDesktopBlocker();
  }
  if (Platform.isWindows) return WindowsDesktopBlocker();
  if (Platform.isLinux) return LinuxDesktopBlocker();
  return stub.createDesktopBlocker();
}
