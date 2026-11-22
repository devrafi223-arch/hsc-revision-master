// Conditional export: native platforms save a real file with
// path_provider; web copies the JSON to the clipboard instead.
export 'backup_io.dart' if (dart.library.js_interop) 'backup_web.dart';
