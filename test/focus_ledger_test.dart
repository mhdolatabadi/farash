import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/focus/focus_view.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('Ledger focus uses a clear clock instead of a sunken ring', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final timer = FocusController();
      addTearDown(timer.dispose);

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

      expect(find.text('۲۵:۰۰'), findsOneWidget);
      expect(find.text('نوبت تمرکز'), findsOneWidget);
      expect(find.text('آمادهٔ شروع'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
