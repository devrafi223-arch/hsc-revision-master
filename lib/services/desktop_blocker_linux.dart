import 'dart:io';

import 'desktop_blocker_base.dart';

/// Linux foreground-app detection — best effort only.
///
/// Uses `xdotool getactivewindow getwindowpid` + `/proc/<pid>/exe`.
/// Needs xdotool installed; without it this reports unavailable and
/// the UI says so. On Wayland, window listing is restricted by the
/// compositor, so even with xdotool this may not see other apps —
/// Linux blocking is never claimed as full blocking.
class LinuxDesktopBlocker implements DesktopBlocker {
  bool? _hasXdotool;
  bool? _hasWmctrl;

  @override
  bool get isSupported => true;

  @override
  bool get isAvailable => true; // checked lazily; see unavailableReason

  @override
  String get unavailableReason =>
      'Best effort only — install wmctrl and xdotool for PC blocking '
      '(and note Wayland may hide other apps from it).';

  Future<bool> _commandExists(String command) async {
    try {
      final result = await Process.run(
        'sh',
        ['-c', 'command -v $command'],
      ).timeout(const Duration(seconds: 2));
      return (result.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _has(String tool, bool? cache) async {
    if (cache != null) return cache;
    final found = await _commandExists(tool);
    if (tool == 'xdotool') {
      _hasXdotool = found;
    } else {
      _hasWmctrl = found;
    }
    return found;
  }

  @override
  Future<String?> foregroundExe() async {
    try {
      if (!await _has('xdotool', _hasXdotool)) return null;
      final pidResult = await Process.run(
        'xdotool',
        ['getactivewindow', 'getwindowpid'],
      ).timeout(const Duration(seconds: 2));
      final pid = (pidResult.stdout as String).trim();
      if (pid.isEmpty || int.tryParse(pid) == null) return null;
      final link = await Link('/proc/$pid/exe').target();
      final slash = link.lastIndexOf('/');
      final base = slash >= 0 ? link.substring(slash + 1) : link;
      return base.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> bringAppToFront() async {
    try {
      if (await _has('xdotool', _hasXdotool)) {
        await Process.run(
          'xdotool',
          ['search', '--name', 'hsc_revision_master', 'windowactivate'],
        ).timeout(const Duration(seconds: 2));
      } else if (await _has('wmctrl', _hasWmctrl)) {
        await Process.run(
          'wmctrl',
          ['-a', 'hsc_revision_master'],
        ).timeout(const Duration(seconds: 2));
      }
    } catch (_) {
      // Best effort only.
    }
  }

  @override
  Future<bool> closeForegroundWindow() async {
    try {
      if (!await _has('xdotool', _hasXdotool)) return false;
      final result = await Process.run(
        'xdotool',
        ['getactivewindow', 'windowclose'],
      ).timeout(const Duration(seconds: 2));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
