import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable error from the API body, for example `email_taken`.
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Talks to the Farash API. Feature interfaces are implemented here so that
/// one HTTP client serves the whole app.
class ApiClient {
  ApiClient(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<void> checkHealth() async {
    await _send('GET', '/api/v1/health');
  }

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  /// Sends a request and returns the decoded JSON body (null when empty).
  Future<Object?> _send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on Exception {
      throw const ApiException('اتصال به سرور برقرار نشد.');
    }

    final decoded = response.body.isEmpty
        ? null
        : _tryDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final code = decoded is Map<String, dynamic>
        ? decoded['error'] as String?
        : null;
    throw ApiException(
      _messageFor(response.statusCode, code),
      statusCode: response.statusCode,
      code: code,
    );
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static String _messageFor(int status, String? code) {
    if (status == 401) return 'نشست شما منقضی شده است. دوباره وارد شوید.';
    if (status == 404) return 'پیدا نشد.';
    if (status == 429) {
      return 'درخواست‌ها زیاد است. کمی بعد دوباره امتحان کنید.';
    }
    if (status >= 500) return 'خطای سرور. کمی بعد دوباره امتحان کنید.';
    return 'درخواست انجام نشد.';
  }
}
