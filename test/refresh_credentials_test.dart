import 'dart:convert';

import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('refresh uses opaque credential and returns rotated token', () async {
    final store = MemoryRefreshCredentialStore('old-refresh');
    final api = ApiClient(
      Uri.parse('https://example.invalid'),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/refresh');
        expect(jsonDecode(request.body)['refresh_token'], 'old-refresh');
        return http.Response(
          jsonEncode({
            'token': 'new-access',
            'refresh_token': 'new-refresh',
            'user': {'id': 'u1', 'email': 'test@example.com'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final session = await api.refreshSession((await store.readRefreshToken())!);
    await store.writeRefreshToken(session.refreshToken!);
    expect(session.token, 'new-access');
    expect(await store.readRefreshToken(), 'new-refresh');
  });
}
