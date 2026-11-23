import 'dart:async';

import 'package:flutter/foundation.dart';

import 'desktop_blocker.dart';

/// Polls the foreground app while focus is active and reports blocked
/// apps to the UI. The poll itself is dumb on purpose: the caller
/// decides when blocking applies (session or schedule) and what is
/// allowed; this only watches and reports.
///
/// Always-allowed, whatever the user whitelists: this app itself and
/// the Windows shell (clicking the desktop must not trigger a block).
class DesktopWatcher {
  DesktopWatcher(this._blocker);

  final DesktopBlocker _blocker;

  Timer? _timer;
  String? _lastBlocked;
  bool _busy = false;

  static const Set<String> _alwaysAllowed = {
    'hsc_revision_master.exe',
    'hsc_revision_master',
    'explorer.exe',
  };

  bool get running => _timer != null;

  void start({
    required bool Function() isBlocking,
    required Set<String> allowedExeNames,
    required void Function(String exe) onBlocked,
    required VoidCallback onReturned,
  }) {
    stop();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_busy) return;
      _busy = true;
      try {
        if (!isBlocking()) {
          if (_lastBlocked != null) {
            _lastBlocked = null;
            onReturned();
          }
          return;
        }
        final exe = await _blocker.foregroundExe();
        if (exe == null) return;
        if (_alwaysAllowed.contains(exe) ||
            allowedExeNames.contains(exe)) {
          if (_lastBlocked != null) {
            _lastBlocked = null;
            onReturned();
          }
          return;
        }
        if (_lastBlocked != exe) {
          _lastBlocked = exe;
          await _blocker.bringAppToFront();
          onBlocked(exe);
        }
      } finally {
        _busy = false;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastBlocked = null;
  }
}
