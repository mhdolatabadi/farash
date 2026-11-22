import 'dart:convert';

import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:farash/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('startup 401 retains stored token and allows retry', (tester) async {
    final store = MemorySessionStore('saved-token');
    var meCalls = 0;
    final api = ApiClient(
      Uri.parse('https://example.invalid'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/me') {
          meCalls++;
          if (meCalls == 1) {
            return http.Response(
              jsonEncode({'error': 'unauthorized'}),
              401,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({'user': {'id': 'u1', 'email': 'test@example.com'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    await tester.pumpWidget(FarashApp(
      apiClient: api,
      sessionStore: store,
      healthCheck: () async {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(await store.readToken(), 'saved-token');
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(meCalls, 2);
    expect(await store.readToken(), 'saved-token');
    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
