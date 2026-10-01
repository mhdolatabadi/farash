import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:farash/main.dart';

import 'support/fake_projects_api.dart';
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
    ApiClient? api,
  }) => FarashApp(
    healthCheck: healthCheck ?? () async {},
    apiClient: api ?? fakeServer(),
    sessionStore: sessions ?? MemorySessionStore(),
    projectsApi: FakeProjectsApi(),
    tasksApi: FakeTasksApi(),
  );

  testWidgets('shows the auth screen once the server answers', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('ورود به فراش'), findsOneWidget);
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
    expect(find.text('ورود به فراش'), findsOneWidget);
  });

  testWidgets('signing in saves the token and opens the Inbox', (tester) async {
    final sessions = MemorySessionStore();
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(await sessions.readToken(), 'good-token');
    expect(find.text('هنوز کاری در «صندوق ورودی» نیست.'), findsOneWidget);
  });

  testWidgets('restores a saved session straight into the app', (tester) async {
    await tester.pumpWidget(app(sessions: MemorySessionStore('good-token')));
    await tester.pumpAndSettle();

    expect(find.text('هنوز کاری در «صندوق ورودی» نیست.'), findsOneWidget);
  });

  testWidgets('a rejected saved token is dropped', (tester) async {
    final sessions = MemorySessionStore('expired-token');
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    expect(find.text('ورود به فراش'), findsOneWidget);
    expect(await sessions.readToken(), isNull);
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

  testWidgets('signing out forgets the token', (tester) async {
    final sessions = MemorySessionStore('good-token');
    await tester.pumpWidget(app(sessions: sessions));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('خروج'));
    await tester.pumpAndSettle();

    expect(find.text('ورود به فراش'), findsOneWidget);
    expect(await sessions.readToken(), isNull);
  });

  testWidgets('lays the app out right to left', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final context = tester.element(find.text('ورود به فراش'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
