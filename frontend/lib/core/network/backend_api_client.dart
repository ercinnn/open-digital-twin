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
class BackendApiClient {
  BackendApiClient({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(body ?? const <String, dynamic>{}),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw BackendException(0, 'Cannot reach backend at $baseUrl ($e). Is the FastAPI server running?');
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    final http.Response response;
    try {
      response = await _client.get(uri, headers: const {'Accept': 'application/json'});
    } on Exception catch (e) {
      throw BackendException(0, 'Cannot reach backend at $baseUrl ($e).');
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final dynamic decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{'data': decoded};
    }
    final detail = decoded is Map<String, dynamic> ? decoded['detail'] : null;
    throw BackendException(response.statusCode, detail?.toString() ?? text);
  }

  void close() => _client.close();
}
