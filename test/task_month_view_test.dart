import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/calendar/task_month_view.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Future<List<Task>> Function(DateTime, DateTime) loader) =>
      MaterialApp(
        home: CalendarScope(
          settings: CalendarSettings(),
          child: Scaffold(
            body: TaskMonthView(
              loadTasks: loader,
              now: () => DateTime(2026, 11, 23),
            ),
          ),
        ),
      );

  testWidgets('month displays tasks and navigates months', (tester) async {
    await tester.pumpWidget(app((from, to) async => [
      Task(
        id: 'task1',
        projectId: 'inbox',
        title: 'مطالعه',
        due: TaskDue.onDay(DateTime(2026, 11, 23)),
      ),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsOneWidget);
    await tester.tap(find.byTooltip('ماه بعد'));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsNothing);
    await tester.tap(find.text('امروز'));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsOneWidget);
  });

  testWidgets('month shows retry after loading error', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app((from, to) async {
      if (++calls == 1) throw StateError('offline');
      return [];
    }));
    await tester.pumpAndSettle();
    expect(find.text('دریافت کارهای تقویم ممکن نشد.'), findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('برای این روز کاری زمان‌بندی نشده است.'), findsOneWidget);
  });
}
