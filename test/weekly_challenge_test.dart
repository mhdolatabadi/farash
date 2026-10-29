import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/progress/weekly_challenge.dart';

void main() {
  testWidgets(
    'challenge validates Persian input, retries failure and fits narrow RTL',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var fail = true;
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: Scaffold(
            body: WeeklyChallenge(
              completed: 3,
              target: 10,
              onSave: (value) async {
                if (fail) throw Exception('offline');
                saved = value;
              },
            ),
          ),
        ),
      );
      expect(find.text('۳ از ۱۰ کار'), findsOneWidget);
      await tester.tap(find.text('تغییر هدف چالش'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '۵۰۱');
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(find.text('عددی بین ۱ و ۵۰۰ وارد کنید.'), findsOneWidget);
      expect(saved, 0);
      await tester.enterText(find.byType(TextFormField), '۲۰');
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(find.text('هدف ذخیره نشد؛ دوباره تلاش کنید.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(saved, 20);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reaching target shows success without overflowing with doubled text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: WeeklyChallenge(
                completed: 12,
                target: 10,
                onSave: (_) async {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('به هدف این هفته رسیدید.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
