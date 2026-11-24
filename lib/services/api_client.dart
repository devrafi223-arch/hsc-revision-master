import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../security/secure_local_storage.dart';

/// Transport for the custom backend (Vercel, replaces Supabase).
///
/// Base URL: https://hsc-revision-master-api.vercel.app
/// Every response is `{ok: true, ...}` or
/// `{ok: false, error: CODE, message}`. Failures throw [ApiException]
/// (never null, never a raw string), so callers — and
/// [AuthService.friendlyError] — can map the error code to a plain
/// sentence.
///
/// Auth: the JWT lives in [SecureLocalStorage] (key `hsc-jwt-v1`) and
/// is sent as `Authorization: Bearer <token>` when [auth] is true.
/// A call with [auth] true and no stored token throws
/// `ApiException(UNAUTHORIZED)` without touching the network.
///
/// NOTE on TLS: the old Supabase client used fail-closed CA pinning
/// (Google Trust Services roots only). The custom backend lives on
/// Vercel, whose edge certificates come from Let's Encrypt and rotate,
/// so that pinning would reject every call. This client uses the
/// platform trust store instead (plain `http.Client`).
class ApiException implements Exception {
  ApiException(this.code, this.message);

  /// Backend error code, e.g. `CODE_INVALID`, `UNAUTHORIZED`,
  /// `EMAIL_NOT_CONFIGURED`. `NETWORK` for transport failures.
  final String code;

  /// Human-readable message from the server (or a transport note).
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static final ApiClient instance = ApiClient();

  static const String baseUrl =
      'https://hsc-revision-master-api.vercel.app';

  final http.Client _client;

  Future<Map<String, dynamic>> get(
    String path, {
    bool auth = false,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query,
    );
    final headers = await _headers(auth: auth);
    late http.Response res;
    try {
      res = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        'NETWORK',
        'The request timed out — check your connection and try again.',
      );
    } catch (e) {
      throw _asApiException(e);
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers(auth: auth);
    late http.Response res;
    try {
      res = await _client
          .post(
            uri,
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        'NETWORK',
        'The request timed out — check your connection and try again.',
      );
    } catch (e) {
      throw _asApiException(e);
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    bool auth = false,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query,
    );
    final headers = await _headers(auth: auth);
    late http.Response res;
    try {
      res = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException(
        'NETWORK',
        'The request timed out — check your connection and try again.',
      );
    } catch (e) {
      throw _asApiException(e);
    }
    return _decode(res);
  }

  /// Raw image upload (POST /api/upload?filename=&kind=). The server
  /// wants the raw image bytes with an image/* Content-Type — NOT
  /// multipart.
  Future<Map<String, dynamic>> uploadImage({
    required String filename,
    required String kind,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uri = Uri.parse('$baseUrl/api/upload').replace(
      queryParameters: {'filename': filename, 'kind': kind},
    );
    final headers = await _headers(auth: true);
    headers['Content-Type'] = contentType;
    final request = http.Request('POST', uri)
      ..headers.addAll(headers)
      ..bodyBytes = bytes;
    late http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException(
        'NETWORK',
        'The upload timed out — check your connection and try again.',
      );
    } catch (e) {
      throw _asApiException(e);
    }
    final res = await http.Response.fromStream(streamed);
    return _decode(res);
  }

  Future<Map<String, String>> _headers({required bool auth}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await SecureLocalStorage.readToken();
      if (token == null || token.isEmpty) {
        throw ApiException('UNAUTHORIZED', 'Please log in to continue.');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(res.body);
      body = decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      throw ApiException(
        'SERVER_ERROR',
        'The server returned an unreadable response (${res.statusCode}).',
      );
    }
    if (body['ok'] == true) return body;
    final code = (body['error'] as String?) ?? 'SERVER_ERROR';
    final message =
        (body['message'] as String?) ?? 'Something went wrong on the server.';
    throw ApiException(code, message);
  }

  ApiException _asApiException(Object e) {
    if (e is ApiException) return e;
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('Connection reset') ||
        text.contains('ClientException')) {
      return ApiException(
        'NETWORK',
        'No internet connection — check your Wi-Fi or mobile data and try again.',
      );
    }
    return ApiException(
      'NETWORK',
      text.replaceFirst(RegExp(r'^Exception: '), ''),
    );
  }
}
