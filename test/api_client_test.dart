import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farash/core/api/api_client.dart';

void main() {
  test('health check calls /api/v1/health under the base path', () async {
    late Uri called;
    final client = ApiClient(
      Uri.parse('https://todo.example.com/farash/'),
      client: MockClient((request) async {
        called = request.url;
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    await client.checkHealth();

    expect(called.toString(), 'https://todo.example.com/farash/api/v1/health');
  });

  test('turns an error body into an ApiException with its code', () async {
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient(
        (_) async => http.Response('{"error":"database_unavailable"}', 503),
      ),
    );

    await expectLater(
      client.checkHealth(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.code, 'code', 'database_unavailable'),
      ),
    );
  });

  test('a network failure becomes an ApiException', () async {
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((_) async => throw http.ClientException('down')),
    );

    await expectLater(client.checkHealth(), throwsA(isA<ApiException>()));
  });
}
