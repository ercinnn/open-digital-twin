import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class BackendException implements Exception {
  const BackendException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => statusCode == 0 ? message : 'Backend error $statusCode: $message';
}

/// Thin JSON client for the FastAPI backend (`BACKEND_URL`).
///
/// Every request carries the signed-in user's Supabase access token
/// (`Authorization: Bearer ...`); the backend only serves editors.
class BackendApiClient {
  BackendApiClient({required this.baseUrl, this.accessToken, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;

  /// Returns the current Supabase session token, or null when signed out.
  final String? Function()? accessToken;

  final http.Client _client;

  Map<String, String> _headers({bool json = false}) {
    final token = accessToken?.call();
    return {
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  BackendException _unreachable(Object error) => BackendException(
    0,
    'Cannot reach the backend at $baseUrl ($error). '
    'A sleeping cloud backend needs 1-2 minutes to wake up - try again shortly.',
  );

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response response;
    try {
      response = await _client
          .post(uri, headers: _headers(json: true), body: jsonEncode(body ?? const <String, dynamic>{}))
          .timeout(timeout);
    } on Exception catch (e) {
      throw _unreachable(e);
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> getJson(String path, {Duration timeout = const Duration(seconds: 30)}) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response response;
    try {
      response = await _client.get(uri, headers: _headers()).timeout(timeout);
    } on Exception catch (e) {
      throw _unreachable(e);
    }
    return _decode(response);
  }

  /// Polls `GET /health` until the backend answers, so a sleeping cloud
  /// instance (e.g. a Hugging Face Space) can wake up before real work starts.
  Future<void> waitUntilReady({
    Duration timeout = const Duration(minutes: 4),
    Duration interval = const Duration(seconds: 5),
    void Function(Duration waited)? onWaiting,
  }) async {
    final started = DateTime.now();
    while (true) {
      try {
        final health = await getJson('/health', timeout: const Duration(seconds: 20));
        if (health['status'] == 'ok') return;
      } on BackendException catch (e) {
        // 4xx other than 404/408/429 means the server is up but misconfigured: stop waiting.
        final transient = e.statusCode == 0 || e.statusCode >= 500 || const {404, 408, 429}.contains(e.statusCode);
        if (!transient) rethrow;
      } on FormatException {
        // Wake-up / loading pages are HTML, not JSON.
      }
      final waited = DateTime.now().difference(started);
      if (waited >= timeout) {
        throw BackendException(0, 'The backend at $baseUrl did not become ready within ${timeout.inMinutes} min.');
      }
      onWaiting?.call(waited);
      await Future<void>.delayed(interval);
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final dynamic decoded;
    try {
      decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      throw BackendException(response.statusCode, 'Unexpected non-JSON response');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'data': decoded};
    }
    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    throw BackendException(response.statusCode, detail?.toString() ?? text);
  }

  void close() => _client.close();
}
