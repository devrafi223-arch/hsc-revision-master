// Stub used on web (dart:io does not exist there, so TLS pinning is the
// browser's job). Same API as pinned_http_client.dart; see pinning.dart.
import 'package:http/http.dart' as http;

/// No-op on web: there is no dart:io HttpClient to override.
void installPinnedHttpOverrides() {}

/// No pinned client on web — Supabase uses the browser's fetch/XHR.
http.Client? buildPinnedHttpClient() => null;
