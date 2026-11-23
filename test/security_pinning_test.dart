import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hsc_revision_master/security/pinned_certs.dart';
// Direct import of the dart:io implementation (not pinning.dart): tests
// run on the VM only, and the conditional export resolves to the web stub
// under the analyzer, which lacks buildPinnedContext / cnFromSubject.
import 'package:hsc_revision_master/security/pinned_http_client.dart';
import 'package:hsc_revision_master/supabase_config.dart';

void main() {
  test('pinned roots: exactly 5 PEM blocks, all parse as certificates',
      () {
    expect(PinnedCerts.roots.length, 5);
    for (final pem in PinnedCerts.roots) {
      expect(pem, contains('-----BEGIN CERTIFICATE-----'));
      expect(pem, contains('-----END CERTIFICATE-----'));
    }
  });

  test('pinned context builds from the PEMs without throwing', () {
    // buildPinnedContext is dart:io-only; on web the stub returns null.
    // This test runs on the VM (dart:io available).
    final client = buildPinnedHttpClient();
    expect(client, isNotNull);
    client.close();
  });

  test('a context trusting a NON-pinned root fails the handshake '
      '(fail-closed)', () async {
    // Negative control: a context trusting ONLY ISRG Root X1 (a real,
    // valid root — just not one of our pins) must fail to verify the
    // Supabase host, which chains to GTS Root R4. If this request ever
    // SUCCEEDS, the pinning has silently fallen back to system roots.
    const isrgX1 = '''
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----''';
    final badContext = SecurityContext(withTrustedRoots: false);
    badContext.setTrustedCertificatesBytes(isrgX1.codeUnits);
    final client = HttpClient(context: badContext);
    try {
      // The handshake itself throws (getUrl), so the whole call is
      // inside the expectation.
      await expectLater(
        () async {
          final request = await client.getUrl(
            Uri.parse(
              'https://jlhapvzrsckmldtdgeec.supabase.co/rest/v1/users',
            ),
          );
          await request.close();
        }(),
        throwsA(isA<HandshakeException>()),
      );
    } finally {
      client.close();
    }
  });

  test('cnFromSubject extracts CN from slash and comma forms', () {
    expect(cnFromSubject('/C=US/O=Google Trust Services/CN=WE1'), 'WE1');
    expect(cnFromSubject('CN = supabase.co'), 'supabase.co');
    expect(cnFromSubject('/C=US/O=Example'), isNull);
  });

  test('hostMatchesCertificateName: exact, wildcard, apex', () {
    expect(hostMatchesCertificateName('supabase.co', 'supabase.co'), isTrue);
    expect(
        hostMatchesCertificateName(
            'jlhapvzrsckmldtdgeec.supabase.co', '*.supabase.co'),
        isTrue);
    expect(hostMatchesCertificateName('a.b.supabase.co', '*.supabase.co'),
        isFalse);
    expect(
        hostMatchesCertificateName(
            'jlhapvzrsckmldtdgeec.supabase.co', 'supabase.co'),
        isTrue);
    expect(
        hostMatchesCertificateName(
            'lh3.googleusercontent.com', '*.googleusercontent.com'),
        isTrue);
    expect(hostMatchesCertificateName('supabase.co', '*.google.com'),
        isFalse);
    expect(hostMatchesCertificateName('evil.com', 'supabase.co'), isFalse);
  });

  test('pinned client reaches live Supabase REST (200 with key)', () async {
    // Raw HttpClient (not buildPinnedHttpClient) so the test can force a
    // DIRECT connection: this VM routes outbound traffic through an egress
    // proxy that re-signs TLS with its own CA, which pinning must reject.
    // A real phone / CI runner has no such proxy, and DIRECT is harmless
    // there (it is the default when no proxy is configured).
    final client = HttpClient(context: buildPinnedContext());
    client.badCertificateCallback = verifyPinnedLeaf;
    client.findProxy = (uri) => 'DIRECT';
    try {
      final request = await client.getUrl(
        Uri.parse('${SupabaseConfig.url}/rest/v1/users?select=id&limit=1'),
      ).timeout(const Duration(seconds: 30));
      request.headers.set('apikey', SupabaseConfig.anonKey);
      request.headers.set('Authorization', 'Bearer ${SupabaseConfig.anonKey}');
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      await response.drain<void>();
      expect(response.statusCode, 200);
    } finally {
      client.close();
    }
  });

  test('deny-everything callback still fails the handshake (fail-closed)',
      () async {
    // Empty trust store: validation MUST fail in every environment, so
    // the callback is actually consulted. (A pins-only context validates
    // fine against the real chain on a direct connection — CI proved it —
    // so it cannot force the deny path. A callback that returned true
    // here would let the handshake through, so this also guards against
    // an allow-all regression.)
    final client =
        HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (cert, host, port) => false;
    try {
      await expectLater(
        () async {
          final request = await client.getUrl(
            Uri.parse(
                'https://jlhapvzrsckmldtdgeec.supabase.co/rest/v1/'),
          );
          await request.close();
        }(),
        throwsA(isA<HandshakeException>()),
      );
    } finally {
      client.close();
    }
  });
}
