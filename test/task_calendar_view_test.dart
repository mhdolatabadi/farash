import 'dart:async';

import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/calendar/task_calendar_view.dart';
import 'package:farash/features/calendar/task_month_view.dart';
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

  testWidgets('week shows timed and all-day work across seven dates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          Task(
            id: 'meeting',
            projectId: 'inbox',
            title: 'جلسهٔ فنی',
            due: TaskDue.at(DateTime(2026, 11, 23, 12), 'UTC'),
            durationMinutes: 90,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('week-all-day-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-all-day-b')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('week-timed-meeting-2')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('week-day-2026-11-24')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('week-all-day-a')));
    await tester.pumpAndSettle();
    expect(find.text('بستن'), findsOneWidget);
  });

  testWidgets('switching to month keeps the calendar as a native Farash view', (
    tester,
  ) async {
    await tester.pumpWidget(app((from, to) async => []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ماه'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskMonthView), findsOneWidget);
    await tester.tap(find.text('هفته'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskMonthView), findsNothing);
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

  testWidgets('narrow RTL layout does not overflow and keeps today controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app((from, to) async => []));
    await tester.pumpAndSettle();
    expect(find.text('تمام‌روز'), findsOneWidget);
    expect(find.text('امروز'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
