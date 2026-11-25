import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/focus/focus_view.dart';

void main() {
  testWidgets('cancel reset keeps an active focus session running', (
    tester,
  ) async {
    final timer = FocusController();
    addTearDown(timer.dispose);
    timer.start();
    await tester.pumpWidget(MaterialApp(home: FocusView(controller: timer)));

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();
    expect(find.text('شروع دوبارهٔ نوبت؟'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();

    expect(timer.running, isTrue);
    expect(find.text('شروع دوبارهٔ نوبت؟'), findsNothing);
    // A running timer creates a periodic ticker; stop it before test teardown.
    timer.pause();
  });

  testWidgets('confirm reset discards the active session', (tester) async {
    final timer = FocusController();
    addTearDown(timer.dispose);
    timer.start();
    await tester.pumpWidget(MaterialApp(home: FocusView(controller: timer)));

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('از نو').last);
    await tester.pumpAndSettle();

    expect(timer.running, isFalse);
    expect(timer.remaining, const Duration(minutes: 25));
    expect(timer.progress, 0);
  });

  testWidgets('pristine session resets without a confirmation dialog', (
    tester,
  ) async {
    final timer = FocusController();
    addTearDown(timer.dispose);
    await tester.pumpWidget(MaterialApp(home: FocusView(controller: timer)));

    await tester.tap(find.byIcon(Icons.restart_alt));
    await tester.pumpAndSettle();

    expect(find.text('شروع دوبارهٔ نوبت؟'), findsNothing);
    expect(timer.remaining, const Duration(minutes: 25));
  });
}
