import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/auth/data/token_store.dart';
import 'package:farash/main.dart';

import 'support/fake_auth_api.dart';

void main() {
  Widget app({Future<void> Function()? healthCheck, TokenStore? tokens}) =>
      FarashApp(
        healthCheck: healthCheck ?? () async {},
        authApi: FakeAuthApi(),
        tokenStore: tokens ?? MemoryTokenStore(),
      );

  testWidgets('shows sign-in once the server answers', (tester) async {
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

  testWidgets('restores a saved session straight into the app', (tester) async {
    await tester.pumpWidget(
      app(tokens: MemoryTokenStore('token-a@example.com')),
    );
    await tester.pumpAndSettle();

    expect(find.text('به فراش خوش آمدید'), findsOneWidget);
  });

  testWidgets('lays the app out right to left', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final context = tester.element(find.text('ورود به فراش'));
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
