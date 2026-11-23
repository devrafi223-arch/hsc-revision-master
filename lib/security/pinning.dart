// Conditional export: the real pinning implementation on dart:io
// platforms (Android / Windows / Linux), a no-op stub on web.
export 'pinned_http_client_stub.dart'
    if (dart.library.io) 'pinned_http_client.dart';
