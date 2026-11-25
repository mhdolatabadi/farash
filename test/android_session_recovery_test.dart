import 'dart:convert';

import 'package:menval/core/api/api_client.dart';
import 'package:menval/features/auth/session_store.dart';
import 'package:menval/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('startup 401 retains stored token and allows retry', (
    tester,
  ) async {
    final store = MemorySessionStore('saved-token');
    var meCalls = 0;
    final api = ApiClient(
      Uri.parse('https://example.invalid'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/renew') {
          // An older backend does not yet offer legacy access renewal.
          return http.Response(
            jsonEncode({'error': 'not_found'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }
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
            jsonEncode({
              'user': {'id': 'u1', 'email': 'test@example.com'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MenvalApp(apiClient: api, sessionStore: store, healthCheck: () async {}),
    );
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

  testWidgets('valid legacy Android token upgrades and persists both credentials', (
    tester,
  ) async {
    final access = MemorySessionStore('legacy-access');
    final refresh = MemoryRefreshCredentialStore();
    var renewCalls = 0;
    final api = ApiClient(
      Uri.parse('https://example.invalid'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/renew') {
          renewCalls++;
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer legacy-access');
          return http.Response(
            jsonEncode({
              'token': 'new-access',
              'refresh_token': 'new-refresh',
              'user': {'id': 'u1', 'email': 'test@example.com'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/me') {
          fail('successful renewal must not revalidate the old access token');
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MenvalApp(
        apiClient: api,
        sessionStore: access,
        refreshCredentialStore: refresh,
        healthCheck: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(renewCalls, 1);
    expect(await access.readToken(), 'new-access');
    expect(await refresh.readRefreshToken(), 'new-refresh');
    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired legacy bearer does not renew or clear saved credentials', (
    tester,
  ) async {
    final access = MemorySessionStore('expired-access');
    final refresh = MemoryRefreshCredentialStore();
    final api = ApiClient(
      Uri.parse('https://example.invalid'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/renew') {
          return http.Response(
            jsonEncode({'error': 'invalid_token'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      MenvalApp(
        apiClient: api,
        sessionStore: access,
        refreshCredentialStore: refresh,
        healthCheck: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(await access.readToken(), 'expired-access');
    expect(await refresh.readRefreshToken(), isNull);
    expect(tester.takeException(), isNull);
  });
}
