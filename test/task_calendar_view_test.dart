import 'dart:async';

import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/calendar/task_calendar_view.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(CalendarTaskLoader loader) => MaterialApp(
    home: CalendarScope(
      settings: CalendarSettings(),
      child: TaskCalendarView(
        loadTasks: loader,
        now: () => DateTime(2026, 11, 23),
      ),
    ),
  );

  testWidgets('selecting a day shows only its due tasks', (tester) async {
    await tester.pumpWidget(
      app(
        (from, to) async => [
          Task(
            id: 'a',
            projectId: 'inbox',
            title: 'کار دوشنبه',
            due: TaskDue.onDay(DateTime(2026, 11, 23)),
          ),
          Task(
            id: 'b',
            projectId: 'inbox',
            title: 'کار سه‌شنبه',
            due: TaskDue.onDay(DateTime(2026, 11, 24)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('کار دوشنبه'), findsOneWidget);
    expect(find.text('کار سه‌شنبه'), findsNothing);
    await tester.tap(find.bySemanticsLabel('سه‌شنبه ۳ آذر'));
    await tester.pumpAndSettle();
    expect(find.text('کار سه‌شنبه'), findsOneWidget);
    expect(find.text('کار دوشنبه'), findsNothing);
  });

  testWidgets('a stale previous-week response never replaces new week', (
    tester,
  ) async {
    final first = Completer<List<Task>>();
    var calls = 0;
    await tester.pumpWidget(
      app((from, to) {
        calls++;
        if (calls == 1) return first.future;
        return Future.value([
          Task(
            id: 'new',
            projectId: 'inbox',
            title: 'کار هفته جدید',
            due: TaskDue.onDay(DateTime(2026, 11, 30)),
          ),
        ]);
      }),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('هفتهٔ بعد'));
    await tester.pumpAndSettle();
    expect(find.text('کار هفته جدید'), findsOneWidget);
    first.complete([
      Task(
        id: 'old',
        projectId: 'inbox',
        title: 'دادهٔ قدیمی',
        due: TaskDue.onDay(DateTime(2026, 11, 23)),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('دادهٔ قدیمی'), findsNothing);
    expect(find.text('کار هفته جدید'), findsOneWidget);
  });
}
