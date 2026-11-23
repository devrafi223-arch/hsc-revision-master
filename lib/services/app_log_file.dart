// Conditional export: real file logging on dart:io platforms
// (Android / Windows / Linux), a no-op stub on web.
export 'app_log_file_stub.dart'
    if (dart.library.io) 'app_log_file_io.dart';
