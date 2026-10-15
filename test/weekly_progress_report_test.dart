import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/progress/week_report.dart';

ProgressWeekReport report(int count, int previous) =>
    ProgressWeekReport.fromJson({
      'completed': count,
      'previous_completed': previous,
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'date': DateTime(
              2026,
              10,
              10 + i,
            ).toIso8601String().substring(0, 10),
            'completed': i == 0 ? count : 0,
            'future': i > 4,
          },
      ],
    });

void main() {
  for (final values in [
    (3, 1, '۲ کار بیشتر'),
    (1, 3, '۲ کار کمتر'),
    (0, 0, 'برابر با'),
  ]) {
    testWidgets(
      'weekly comparison ${values.$1}/${values.$2} fits narrow RTL with large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: WeeklyProgressReport(
                  report: report(values.$1, values.$2),
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining(values.$3), findsOneWidget);
        await tester.tap(find.text('گزارش این هفته'));
        await tester.pumpAndSettle();
        expect(find.text('شنبه'), findsOneWidget);
        expect(find.text('هنوز نرسیده'), findsNWidgets(2));
        expect(find.text('۰ کار'), findsNWidgets(values.$1 == 0 ? 5 : 4));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
