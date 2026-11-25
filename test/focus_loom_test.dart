import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/focus/focus_loom.dart';
import 'package:menval/features/focus/focus_view.dart';

void main() {
  test('the original loom advances exactly ten distinct stages', () {
    expect(const FocusLoom(progress: 0).stages, 0);
    expect(const FocusLoom(progress: .001).stages, 1);
    expect(const FocusLoom(progress: .1).stages, 1);
    expect(const FocusLoom(progress: .51).stages, 6);
    expect(const FocusLoom(progress: 1).stages, 10);
  });

  for (final dark in [false, true]) {
    testWidgets('Focus paints an empty loom and then actual session progress', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timer = FocusController();
      addTearDown(timer.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(body: FocusView(controller: timer)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FocusLoom), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.bySemanticsLabel('فرش تمرکز: ۰ از ۱۰ مرحله بافته شد'),
        findsOneWidget,
      );
      expect(tester.widget<FocusLoom>(find.byType(FocusLoom)).stages, 0);
      final painter = find.descendant(
        of: find.byType(FocusLoom),
        matching: find.byType(CustomPaint),
      );
      expect(painter, findsOneWidget);

      timer.restoreRemaining(const Duration(minutes: 10));
      await tester.pump();
      expect(tester.widget<FocusLoom>(find.byType(FocusLoom)).stages, 6);
      timer.reset();
      await tester.pump();
      expect(tester.widget<FocusLoom>(find.byType(FocusLoom)).stages, 0);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
