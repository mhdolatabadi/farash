import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/tasks/presentation/due_tasks_view.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/offline/offline_read_cache.dart';
import 'package:menval/features/auth/session_store.dart';
import 'package:menval/main.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

/// Answers the auth endpoints for one account, a@example.com / password1.
ApiClient fakeServer({bool offline = false}) => ApiClient(
  Uri.parse('https://todo.example.com'),
  client: MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    final user = {'id': 'u1', 'email': 'a@example.com'};
    switch (request.url.path) {
      case '/api/v1/me':
        return request.headers['Authorization'] == 'Bearer good-token'
            ? http.Response(jsonEncode({'user': user}), 200)
            : http.Response('{"error":"invalid_token"}', 401);
      case '/api/v1/auth/login':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return body['password'] == 'password1'
            ? http.Response(
                jsonEncode({'token': 'good-token', 'user': user}),
                200,
              )
            : http.Response('{"error":"invalid_credentials"}', 401);
    }
    return http.Response('{"error":"not_found"}', 404);
  }),
);

void main() {
  Widget app({
    Future<void> Function()? healthCheck,
    SessionStore? sessions,
    RefreshCredentialStore? refreshCredentials,
    ApiClient? api,
  }) => MenvalApp(
    healthCheck: healthCheck ?? () async {},
    apiClient: api ?? fakeServer(),
    sessionStore: sessions ?? MemorySessionStore(),
    refreshCredentialStore: refreshCredentials,
    projectsApi: FakeProjectsApi(),
    tasksApi: FakeTasksApi(),
    sectionsApi: FakeSectionsApi(),
  );

  testWidgets('shows the auth screen once the server answers', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('ورود به منوال'), findsOneWidget);
  });

  testWidgets('the password can be shown and hidden', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    bool obscured() => tester
        .widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'رمز عبور'),
            matching: find.byType(EditableText),
          ),
        )
        .obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('نمایش رمز'));
    await tester.pump();
    expect(obscured(), isFalse);
    await tester.tap(find.byTooltip('پنهان کردن رمز'));
    await tester.pump();
    expect(obscured(), isTrue);
  });

  testWidgets('offers a retry while the server is unreachable', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        healthCheck: () async {
          calls++;
          if (calls == 1) throw Exception('offline');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اتصال به سرور برقرار نشد'), findsOneWidget);

    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('ورود به منوال'), findsOneWidget);
  });

  testWidgets('signing in saves the token and opens today', (tester) async {
    final sessions = MemorySessionStore();
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(await sessions.readToken(), 'good-token');
    expect(find.byType(DueTasksView), findsOneWidget);
  });

  testWidgets('restores a saved session straight into the app', (tester) async {
    await tester.pumpWidget(app(sessions: MemorySessionStore('good-token')));
    await tester.pumpAndSettle();

    expect(find.byType(DueTasksView), findsOneWidget);
  });

  testWidgets('a rejected saved token stays locked for retry', (tester) async {
    final sessions = MemorySessionStore('expired-token');
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(find.byType(DueTasksView), findsNothing);
    expect(await sessions.readToken(), 'expired-token');
  });

  testWidgets('a network failure keeps the saved token for a retry', (
    tester,
  ) async {
    final sessions = MemorySessionStore('good-token');
    await tester.pumpWidget(
      app(sessions: sessions, api: fakeServer(offline: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(await sessions.readToken(), 'good-token');
  });

  testWidgets(
    'a rotated refresh rejected by the server recovers with valid access',
    (tester) async {
      final saved = MemorySessionStore('good-token');
      final refresh = MemoryRefreshCredentialStore('already-rotated');
      var refreshAttempts = 0;
      final api = ApiClient(
        Uri.parse('https://todo.example.com'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            refreshAttempts++;
            return http.Response('{"error":"invalid_refresh_token"}', 401);
          }
          if (request.url.path == '/api/v1/me') {
            expect(request.headers['Authorization'], 'Bearer good-token');
            return http.Response(
              jsonEncode({
                'user': {'id': 'u1', 'email': 'a@example.com'},
              }),
              200,
            );
          }
          return http.Response('{"error":"not_found"}', 404);
        }),
      );
      await tester.pumpWidget(
        app(sessions: saved, refreshCredentials: refresh, api: api),
      );
      await tester.pumpAndSettle();

      expect(refreshAttempts, 1);
      expect(find.byType(DueTasksView), findsOneWidget);
      expect(await saved.readToken(), 'good-token');
      // A stale refresh must not erase a concurrently rotated credential.
      expect(await refresh.readRefreshToken(), 'already-rotated');
    },
  );

  testWidgets('another browser tab rotation keeps its newest credentials', (
    tester,
  ) async {
    final saved = MemorySessionStore('old-access');
    final refresh = MemoryRefreshCredentialStore('old-refresh');
    final api = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          // Simulate another tab finishing a successful refresh first.
          await saved.writeToken('new-access');
          await refresh.writeRefreshToken('new-refresh');
          return http.Response('{"error":"invalid_refresh_token"}', 401);
        }
        if (request.url.path == '/api/v1/me') {
          expect(request.headers['Authorization'], 'Bearer new-access');
          return http.Response(
            jsonEncode({
              'user': {'id': 'u1', 'email': 'a@example.com'},
            }),
            200,
          );
        }
        return http.Response('{"error":"not_found"}', 404);
      }),
    );
    await tester.pumpWidget(
      app(sessions: saved, refreshCredentials: refresh, api: api),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DueTasksView), findsOneWidget);
    expect(await saved.readToken(), 'new-access');
    expect(await refresh.readRefreshToken(), 'new-refresh');
  });

  testWidgets(
    'a temporary refresh outage keeps the credential when access works',
    (tester) async {
      final saved = MemorySessionStore('good-token');
      final refresh = MemoryRefreshCredentialStore('still-valid-refresh');
      final api = ApiClient(
        Uri.parse('https://todo.example.com'),
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/auth/refresh') {
            throw http.ClientException('temporary outage');
          }
          if (request.url.path == '/api/v1/me') {
            return http.Response(
              jsonEncode({
                'user': {'id': 'u1', 'email': 'a@example.com'},
              }),
              200,
            );
          }
          return http.Response('{"error":"not_found"}', 404);
        }),
      );
      await tester.pumpWidget(
        app(sessions: saved, refreshCredentials: refresh, api: api),
      );
      // The Today screen has ongoing animations; settling every scheduled
      // frame is not a valid readiness signal for reconnect regressions.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DueTasksView), findsOneWidget);
      expect(await refresh.readRefreshToken(), 'still-valid-refresh');
    },
  );

  testWidgets('invalid access and refresh show a safe explicit re-login path', (
    tester,
  ) async {
    final saved = MemorySessionStore('expired-token');
    final refresh = MemoryRefreshCredentialStore('invalid-refresh');
    final api = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          return http.Response('{"error":"invalid_refresh_token"}', 401);
        }
        if (request.url.path == '/api/v1/me') {
          return http.Response('{"error":"invalid_token"}', 401);
        }
        return http.Response('{"error":"not_found"}', 404);
      }),
    );
    await tester.pumpWidget(
      app(sessions: saved, refreshCredentials: refresh, api: api),
    );
    await tester.pumpAndSettle();
    expect(find.text('بازیابی ورود قبلی ممکن نشد'), findsOneWidget);
    expect(find.text('ورود دوباره به حساب'), findsOneWidget);

    await tester.tap(find.text('ورود دوباره به حساب'));
    await tester.pumpAndSettle();
    expect(find.text('ورود به منوال'), findsOneWidget);
    expect(await saved.readToken(), 'expired-token');
    expect(await refresh.readRefreshToken(), 'invalid-refresh');
    expect(find.byType(DueTasksView), findsNothing);
  });

  for (final outcome in [
    'valid',
    'rejected',
    'different-owner',
    'network-outage',
  ]) {
    testWidgets('offline reconnect with $outcome refresh preserves identity', (
      tester,
    ) async {
      final saved = MemorySessionStore('old-access');
      final refresh = MemoryRefreshCredentialStore();
      final cache = OfflineReadCache();
      var oldAccessChecks = 0;
      var refreshAttempts = 0;
      final api = ApiClient(
        Uri.parse('https://todo.example.com'),
        offlineCache: cache,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/me') {
            final bearer = request.headers['Authorization'];
            if (bearer == 'Bearer old-access') {
              oldAccessChecks++;
              if (oldAccessChecks > 1) {
                return http.Response('{"error":"invalid_token"}', 401);
              }
            } else if (bearer != 'Bearer new-access') {
              return http.Response('{"error":"invalid_token"}', 401);
            }
            return http.Response(
              jsonEncode({
                'user': {'id': 'u1', 'email': 'a@example.com'},
              }),
              200,
            );
          }
          // The legacy renewal endpoint is absent on this fixture server.
          // Returning 200 with an empty body would fabricate a bad session.
          if (request.url.path == '/api/v1/auth/renew') {
            return http.Response('{"error":"not_found"}', 404);
          }
          if (request.url.path == '/api/v1/auth/refresh') {
            refreshAttempts++;
            expect(jsonDecode(request.body)['refresh_token'], 'old-refresh');
            if (outcome == 'rejected') {
              return http.Response('{"error":"invalid_refresh_token"}', 401);
            }
            if (outcome == 'network-outage') {
              throw http.ClientException('temporary connection failure');
            }
            return http.Response(
              jsonEncode({
                'token': 'new-access',
                'refresh_token': 'new-refresh',
                'user': {
                  'id': outcome == 'different-owner' ? 'u2' : 'u1',
                  'email': 'a@example.com',
                },
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      await tester.pumpWidget(
        app(sessions: saved, refreshCredentials: refresh, api: api),
      );
      // Let the initial authenticated shell finish its asynchronous startup.
      // The continuously scheduled Today animations only matter after the
      // offline reconnect banner is shown; startup itself can settle.
      await tester.pumpAndSettle();
      expect(find.byType(DueTasksView), findsOneWidget);

      // Simulate an Android app left open until its old access JWT expires.
      await refresh.writeRefreshToken('old-refresh');
      cache.usedOffline();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('اتصال دوباره'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(oldAccessChecks, 2);
      expect(refreshAttempts, 1);
      expect(find.byType(DueTasksView), findsOneWidget);
      expect(find.text('ورود به منوال'), findsNothing);
      if (outcome == 'valid') {
        expect(await saved.readToken(), 'new-access');
        expect(await refresh.readRefreshToken(), 'new-refresh');
        expect(find.text('اتصال دوباره'), findsNothing);
      } else {
        expect(await saved.readToken(), 'old-access');
        expect(await refresh.readRefreshToken(), 'old-refresh');
        expect(find.textContaining('اتصال برقرار نشد'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('signing out forgets the token', (tester) async {
    final sessions = MemorySessionStore('good-token');
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حساب و تنظیمات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خروج'));
    await tester.pumpAndSettle();

    expect(find.text('ورود به منوال'), findsOneWidget);
    expect(await sessions.readToken(), isNull);
  });

  testWidgets('lays the app out right to left', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final context = tester.element(find.text('ورود به منوال'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
  testWidgets('rejects Persian passwords exceeding 72 UTF-8 bytes', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    // 37 Persian letters are 37 Dart code units but 74 UTF-8 bytes.
    await tester.enterText(
      find.byType(TextFormField).at(1),
      List.filled(37, 'ش').join(),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(find.text('رمز عبور باید بین ۸ تا ۷۲ بایت باشد.'), findsOneWidget);
    expect(find.text('ورود به منوال'), findsOneWidget);
  });

  testWidgets('accepts a valid eight-byte Persian password locally', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      List.filled(4, 'ش').join(),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(find.text('رمز عبور باید بین ۸ تا ۷۲ بایت باشد.'), findsNothing);
    // The fake server rejects the credentials, not client-side validation.
    expect(find.text('ورود به منوال'), findsOneWidget);
  });
}
