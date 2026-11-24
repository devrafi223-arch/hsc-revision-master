import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/app_log.dart';

/// App logs viewer (Settings → App logs): everything the app recorded
/// since launch — startup, session restore, auth, errors — so Rafi can
/// copy it and paste it to Arlo when something goes wrong.
///
/// On Windows the same lines also live in a file next to the exe
/// (`logs/hsc-revision-master.log`); the path is shown here so the
/// file can be sent even when the app window stays black.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Theme.of(context).textTheme.bodyMedium!;
    final muted = isDark ? JimColors.darkMuted : JimColors.muted;
    final path = AppLog.logPath;
    return Scaffold(
      appBar: AppBar(
        title: const Text('App logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (path != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(
                  'Log file: $path',
                  style: base.copyWith(fontSize: 12, color: muted),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: SelectableText(
                  AppLog.text.isEmpty ? 'No logs recorded yet.' : AppLog.text,
                  style: base.copyWith(fontSize: 12, height: 1.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: AppLog.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logs copied')),
                        );
                      },
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Copy all logs'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(AppLog.clear),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
