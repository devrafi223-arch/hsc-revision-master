// PC foreground-app detection for desktop Focus Mode.
//
// The real implementation lives in desktop_blocker_io.dart (dart:io);
// on web this resolves to the no-op stub, so the web build keeps
// compiling. All callers use [createDesktopBlocker].
export 'desktop_blocker_base.dart';
export 'desktop_blocker_stub.dart'
    if (dart.library.io) 'desktop_blocker_io.dart';
