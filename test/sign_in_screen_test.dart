import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/auth/application/auth_controller.dart';
import 'package:farash/features/auth/data/token_store.dart';
import 'package:farash/features/auth/presentation/auth_gate.dart';

import 'support/fake_auth_api.dart';

void main() {
  late AuthController auth;

  Future<void> pumpGate(WidgetTester tester, {FakeAuthApi? api}) async {
    auth = AuthController(
      api: api ?? FakeAuthApi(),
      tokenStore: MemoryTokenStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AuthGate(
            controller: auth,
            signedIn: (_) => Scaffold(body: Text('home ${auth.user!.email}')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
  }

  testWidgets('signs in with an existing account', (tester) async {
    await pumpGate(
      tester,
      api: FakeAuthApi(accounts: {'a@example.com': 'password1'}),
    );

    await fill(tester, 'a@example.com', 'password1');
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(find.text('home a@example.com'), findsOneWidget);
  });

  testWidgets('shows the server error for wrong credentials', (tester) async {
    await pumpGate(
      tester,
      api: FakeAuthApi(accounts: {'a@example.com': 'password1'}),
    );

    await fill(tester, 'a@example.com', 'nope-nope');
    await tester.tap(find.widgetWithText(FilledButton, 'ورود'));
    await tester.pumpAndSettle();

    expect(find.text('ایمیل یا رمز عبور درست نیست.'), findsOneWidget);
    expect(auth.status, AuthStatus.signedOut);
  });

  testWidgets('registering checks the password length first', (tester) async {
    await pumpGate(tester);

    await tester.tap(find.text('حساب ندارید؟ ثبت‌نام کنید'));
    await tester.pumpAndSettle();
    await fill(tester, 'new@example.com', 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'ساخت حساب'));
    await tester.pumpAndSettle();

    expect(find.text('رمز عبور باید حداقل ۸ کاراکتر باشد.'), findsOneWidget);

    await fill(tester, 'new@example.com', 'long-enough');
    await tester.tap(find.widgetWithText(FilledButton, 'ساخت حساب'));
    await tester.pumpAndSettle();

    expect(find.text('home new@example.com'), findsOneWidget);
  });

  testWidgets('a taken email explains itself', (tester) async {
    await pumpGate(
      tester,
      api: FakeAuthApi(accounts: {'a@example.com': 'password1'}),
    );

    await tester.tap(find.text('حساب ندارید؟ ثبت‌نام کنید'));
    await tester.pumpAndSettle();
    await fill(tester, 'a@example.com', 'password2');
    await tester.tap(find.widgetWithText(FilledButton, 'ساخت حساب'));
    await tester.pumpAndSettle();

    expect(find.text('با این ایمیل قبلاً حساب ساخته شده است.'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with the keyboard open', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.reset);

    await pumpGate(tester);
    expect(tester.takeException(), isNull);

    // The form scrolls, so every control stays reachable above the keyboard.
    final toggle = find.text('حساب ندارید؟ ثبت‌نام کنید');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(FilledButton, 'ساخت حساب');
    await tester.ensureVisible(button);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });
}
