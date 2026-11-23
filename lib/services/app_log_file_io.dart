import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Log file location. On desktop the file sits next to the exe in a
/// `logs/` folder — easy for Rafi to find and send. On mobile it lives
/// in the app documents folder.
String? _logFilePath;

String? get logFilePath => _logFilePath;

/// Creates the log file and writes a launch header. Never throws.
Future<void> initFileSink() async {
  try {
    final Directory dir;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      dir = Directory('${exeDir.path}${Platform.pathSeparator}logs');
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}${Platform.pathSeparator}logs');
    }
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}hsc-revision-master.log',
    );
    _logFilePath = file.path;
    await file.writeAsString(
      '--- HSC Revision Master log, ${DateTime.now().toIso8601String()} ---\n',
      mode: FileMode.append,
    );
  } catch (_) {
    _logFilePath = null;
  }
}

/// Appends one line to the log file. Never throws.
void appendLineToFile(String line) {
  final path = _logFilePath;
  if (path == null) return;
  try {
    File(path).writeAsStringSync('$line\n', mode: FileMode.append);
  } catch (_) {}
}
