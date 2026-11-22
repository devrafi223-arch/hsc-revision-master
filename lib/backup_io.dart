import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Saves the JSON backup into the app documents directory (Android,
/// Windows, Linux) and returns a human-readable confirmation.
Future<String> saveBackupJson(String json) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/hsc-revision-backup.json');
  await file.writeAsString(json);
  return 'Backup saved to ${file.path}';
}
