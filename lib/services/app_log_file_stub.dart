/// Web has no log file — logs live in memory only (AppLog.lines).
String? get logFilePath => null;

/// No-op on web.
Future<void> initFileSink() async {}

/// No-op on web.
void appendLineToFile(String line) {}
