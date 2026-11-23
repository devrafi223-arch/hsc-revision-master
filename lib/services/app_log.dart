import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_log_file.dart';

/// App diagnostics log — what Rafi asked for: every important event and
/// every error is recorded so a black screen (or any bug) can be sent to
/// Arlo instead of guessed at.
///
/// Two sinks, both best-effort and never throwing:
/// * in-memory ring buffer (last [maxLines] lines), shown in the app
///   (Settings → App logs) and in the auto error popup;
/// * a log FILE on disk (see [logPath]) — on Windows it sits next to
///   the exe in a `logs/` folder, so it exists even when the app never
///   paints a frame. On web there is no file (memory only).
///
/// [init] must run first in main(); after that [info]/[warn]/[error]
/// are safe from anywhere, including before runApp.
class AppLog {
  static const int maxLines = 500;

  static final List<String> _lines = [];

  /// All recorded lines, oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  /// All recorded lines as one block of text.
  static String get text => _lines.join('\n');

  /// Absolute path of the log file, or null when there is none
  /// (web, or the file could not be created).
  static String? get logPath => logFilePath;

  /// The navigator used by the auto error popup. Wired into
  /// MaterialApp in main.dart.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _popupShown = false;

  /// Resolves the log file (if any) and writes a launch header.
  /// Never throws.
  static Future<void> init() async {
    try {
      await initFileSink();
      info('app', 'log started${logPath != null ? ' — file: $logPath' : ''}');
    } catch (_) {}
  }

  static void info(String tag, String message) => _add('INFO', tag, message);

  static void warn(String tag, String message) => _add('WARN', tag, message);

  static void error(String tag, String message) =>
      _add('ERROR', tag, message);

  /// Clears the in-memory buffer (the file is left alone).
  static void clear() => _lines.clear();

  static void _add(String level, String tag, String message) {
    final now = DateTime.now();
    final ts =
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    final line = '[$ts] $level $tag: $message';
    if (_lines.length >= maxLines) _lines.removeAt(0);
    _lines.add(line);
    try {
      appendLineToFile(line);
    } catch (_) {}
    // Also to the console for local debugging.
    // ignore: avoid_print
    print(line);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Shows the auto error popup once per session: the recent log lines
  /// with a Copy button, so Rafi can paste them to Arlo. Does nothing
  /// when the UI is not up yet (e.g. the app is still a black window —
  /// then the log FILE is the record) or when a popup already showed.
  static void maybeShowErrorPopup() {
    if (_popupShown) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;
    _popupShown = true;
    try {
      showDialog<void>(
        context: context,
        builder: (context) {
          final recent = _lines.length > 40
              ? _lines.sublist(_lines.length - 40)
              : _lines;
          return AlertDialog(
            title: const Text('Something went wrong'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(
                  recent.isEmpty
                      ? 'No logs recorded yet.'
                      : recent.join('\n'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logs copied')),
                  );
                },
                child: const Text('Copy logs'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (_) {
      // The popup is a nicety — never let it crash the app.
    }
  }
}
