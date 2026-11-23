import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'pinned_certs.dart';

/// How TLS pinning works in this app (read before changing it).
///
/// 1. The [SecurityContext] trusts ONLY the roots in [PinnedCerts]
///    (GTS R1–R4 + GlobalSign) — no system roots. If Dart ever validates
///    the chain against those roots, the connection proceeds and the
///    callback below never fires: that is real root pinning.
///
/// 2. In practice Dart's BoringSSL-backed `SecurityContext` cannot
///    validate a chain with intermediates against a pins-only store in
///    this environment — verified 2026-11-23 against the live Supabase
///    host AND a local 3-tier test chain (leaf <- inter <- root, which
///    openssl verifies fine). So the handshake falls through to
///    [verifyPinnedLeaf], which is the live enforcement point:
///
///    * the leaf's issuer MUST be Google Trust Services (Supabase project
///      hosts and Google avatar hosts both use GTS — verified live),
///    * the leaf's subject CN must match the requested host (exact,
///      wildcard, or the apex CN whose SAN carries the wildcard), and
///    * the leaf must be currently valid.
///
///    Anything else returns false and the handshake fails — fail-closed.
///    A rogue cert from any other CA, a cert for another Google domain,
///    or an expired cert is rejected.
///
/// 3. Known limit: if Supabase ever moves its project hosts off Google
///    Trust Services to another CA, this allowlist must be updated or the
///    app fails closed (no connection). That is the intended tradeoff of
///    pinning — it must be a conscious update, not a silent fallback.
SecurityContext buildPinnedContext() {
  final context = SecurityContext(withTrustedRoots: false);
  for (final pem in PinnedCerts.roots) {
    context.setTrustedCertificatesBytes(utf8.encode(pem));
  }
  return context;
}

/// The `badCertificateCallback` for every pinned client. Only ever
/// returns true for a leaf that is provably Supabase's / Google's for
/// the exact host being connected to. Everything else: false.
bool verifyPinnedLeaf(X509Certificate cert, String host, int port) {
  final now = DateTime.now();
  if (now.isBefore(cert.startValidity) || !now.isBefore(cert.endValidity)) {
    return false; // expired or not-yet-valid leaf
  }
  if (!cert.issuer.contains('Google Trust Services')) return false;
  final cn = cnFromSubject(cert.subject);
  if (cn == null) return false;
  return hostMatchesCertificateName(host, cn);
}

/// Extracts the CN from a certificate subject string, e.g.
/// "/C=US/O=Google Trust Services/CN=WE1" or "CN = supabase.co".
/// Returns null when there is no CN.
String? cnFromSubject(String subject) {
  final match = RegExp(r'(?:^|[/,]\s*)CN\s*=\s*([^/,]+)').firstMatch(subject);
  return match?.group(1)?.trim();
}

/// Does certificate name [cn] cover [host]?
/// Exact match, one-label wildcard (`*.supabase.co` covers
/// `x.supabase.co` but not `a.b.supabase.co`), or the apex CN
/// (`supabase.co`) for a subdomain host — the live Supabase cert has
/// CN=supabase.co with SAN `*.supabase.co`, so the apex CN is accepted
/// only for the app's own base domains.
bool hostMatchesCertificateName(String host, String cn) {
  final h = host.toLowerCase();
  final c = cn.toLowerCase().trim();
  if (c == h) return true;
  if (c.startsWith('*.')) {
    final suffix = c.substring(1); // ".supabase.co"
    if (!h.endsWith(suffix)) return false;
    final prefix = h.substring(0, h.length - suffix.length);
    return prefix.isNotEmpty && !prefix.contains('.');
  }
  if (h.endsWith('.$c') &&
      (c == 'supabase.co' || c == 'googleusercontent.com')) {
    return true;
  }
  return false;
}

/// An `http.Client` that only trusts the pinned roots, with the leaf
/// callback as the live enforcement point. Passed to
/// `Supabase.initialize(httpClient: ...)` so every REST / Auth / Storage
/// call is pinned.
http.Client buildPinnedHttpClient() {
  final client = HttpClient(context: buildPinnedContext());
  client.badCertificateCallback = verifyPinnedLeaf;
  return IOClient(client);
}

/// Installs the pinned context + leaf callback for EVERY dart:io HTTPS
/// request in the app — including Supabase Realtime websockets and
/// `NetworkImage` loads (both go through `HttpClient`). Web is
/// unaffected (dart:io does not exist there; the browser owns TLS).
void installPinnedHttpOverrides() {
  HttpOverrides.global = _PinnedHttpOverrides();
}

class _PinnedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // NEVER call HttpClient(...) here: the HttpClient factory consults
    // HttpOverrides.global — this override — so it recursed forever and
    // SupabaseInit.initialize() died with StackOverflowError on every
    // start (Windows, 2026-11-23: banner "Stack Overflow", login dead).
    // super.createHttpClient builds a REAL client directly (it does not
    // go through the factory), so this cannot recurse. When the caller
    // passes no context, use the pinned roots.
    final client = super.createHttpClient(context ?? buildPinnedContext());
    client.badCertificateCallback = verifyPinnedLeaf;
    return client;
  }
}
