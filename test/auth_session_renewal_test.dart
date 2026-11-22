import 'dart:convert';

import 'package:farash/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'renewSession sends bearer token and decodes replacement session',
    () async {
      final api = ApiClient(
        Uri.parse('https://example.invalid'),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/auth/renew');
          expect(request.headers['Authorization'], 'Bearer old-token');
          return http.Response(
            jsonEncode({
              'token': 'new-token',
              'user': {'id': 'u1', 'email': 'test@example.com'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final session = await api.renewSession('old-token');
      expect(session.token, 'new-token');
      expect(session.user.id, 'u1');
    },
  );
}
