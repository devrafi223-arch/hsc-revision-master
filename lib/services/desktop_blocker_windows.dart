import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'desktop_blocker_base.dart';

/// Windows foreground-app detection via Win32 FFI (win32 6.x API:
/// typed HWND/HANDLE extension types, Win32Result wrappers).
///
/// Reads the foreground window's process exe name every poll, brings
/// this app's window forward when a blocked app is found, and asks a
/// blocked window to close politely (WM_CLOSE — the dh-blocker "polite
/// quit" step; no force-kill). This file is only ever *called* on
/// Windows; the win32 bindings compile on other native platforms but
/// their functions are never invoked there.
class WindowsDesktopBlocker implements DesktopBlocker {
  static const String _windowTitle = 'hsc_revision_master';

  @override
  bool get isSupported => true;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<String?> foregroundExe() async {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd.address == 0) return null;
      final pidPtr = calloc<Uint32>();
      try {
        GetWindowThreadProcessId(hwnd, pidPtr);
        final pid = pidPtr.value;
        if (pid == 0) return null;
        final opened = OpenProcess(
          PROCESS_QUERY_LIMITED_INFORMATION,
          false,
          pid,
        );
        final hProcess = opened.value;
        if (hProcess.address == 0) return null;
        try {
          final namePtr = calloc<Uint16>(260).cast<Utf16>();
          final sizePtr = calloc<Uint32>()..value = 260;
          try {
            final ok = QueryFullProcessImageName(
              hProcess,
              PROCESS_NAME_WIN32,
              PWSTR(namePtr),
              sizePtr,
            );
            if (!ok.value) return null;
            final fullPath = namePtr.toDartString();
            final slash = fullPath.lastIndexOf('\\');
            final base = slash >= 0
                ? fullPath.substring(slash + 1)
                : fullPath;
            return base.toLowerCase();
          } finally {
            calloc.free(namePtr);
            calloc.free(sizePtr);
          }
        } finally {
          CloseHandle(hProcess);
        }
      } finally {
        calloc.free(pidPtr);
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> bringAppToFront() async {
    try {
      final titlePtr = _windowTitle.toNativeUtf16();
      try {
        final found = FindWindow(null, PCWSTR(titlePtr));
        final hwnd = found.value;
        if (hwnd.address != 0) {
          ShowWindow(hwnd, SW_RESTORE);
          SetForegroundWindow(hwnd);
        }
      } finally {
        calloc.free(titlePtr);
      }
    } catch (_) {
      // Bring-to-front is best effort; the in-app block view still
      // shows when the user comes back to the app.
    }
  }

  @override
  Future<bool> closeForegroundWindow() async {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd.address == 0) return false;
      return PostMessage(hwnd, WM_CLOSE, WPARAM(0), LPARAM(0)).value;
    } catch (_) {
      return false;
    }
  }
}
