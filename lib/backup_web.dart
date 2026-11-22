import 'package:flutter/services.dart';

/// Web has no app documents folder, so the backup JSON is copied to the
/// clipboard — paste it into a note or file to keep it.
Future<String> saveBackupJson(String json) async {
  await Clipboard.setData(ClipboardData(text: json));
  return 'Backup JSON copied to clipboard — paste it into a file to keep it.';
}
