import 'dart:async';

import 'package:menval/core/calendar/calendar_month.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/features/calendar/task_month_view.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Future<List<Task>> Function(DateTime, DateTime) loader, {
    CalendarSettings? settings,
  }) => MaterialApp(
    home: CalendarScope(
      settings: settings ?? CalendarSettings(),
      child: Scaffold(
        body: TaskMonthView(
          loadTasks: loader,
          now: () => DateTime(2026, 11, 23),
        ),
      ),
    ),
  );

  testWidgets('month displays tasks and navigates months', (tester) async {
    await tester.pumpWidget(
      app(
        (from, to) async => [
          Task(
            id: 'task1',
            projectId: 'inbox',
            title: 'مطالعه',
            due: TaskDue.onDay(DateTime(2026, 11, 23)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsOneWidget);
    await tester.tap(find.byTooltip('ماه بعد'));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsNothing);
    await tester.tap(find.text('امروز'));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsOneWidget);
  });

  testWidgets(
    'changing account loader clears tasks and ignores stale results',
    (tester) async {
      final oldResponse = Completer<List<Task>>();
      final newResponse = Completer<List<Task>>();
      Future<List<Task>> oldLoader(DateTime from, DateTime to) =>
          oldResponse.future;
      Future<List<Task>> newLoader(DateTime from, DateTime to) =>
          newResponse.future;

      await tester.pumpWidget(app(oldLoader));
      await tester.pumpWidget(app(newLoader));
      newResponse.complete([
        Task(
          id: 'new-owner',
          projectId: 'inbox',
          title: 'کار حساب جدید',
          due: TaskDue.onDay(DateTime(2026, 11, 23)),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('کار حساب جدید'), findsOneWidget);

      oldResponse.complete([
        Task(
          id: 'old-owner',
          projectId: 'inbox',
          title: 'کار خصوصی حساب قبلی',
          due: TaskDue.onDay(DateTime(2026, 11, 23)),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('کار خصوصی حساب قبلی'), findsNothing);
      expect(find.text('کار حساب جدید'), findsOneWidget);
    },
  );

  testWidgets('changing week start reloads month bounds and ignores old data', (
    tester,
  ) async {
    final settings = CalendarSettings();
    final first = Completer<List<Task>>();
    final ranges = <DateTime>[];
    var calls = 0;
    Future<List<Task>> loader(DateTime from, DateTime to) {
      ranges.add(from);
      if (++calls == 1) return first.future;
      return Future.value([]);
    }

    await tester.pumpWidget(app(loader, settings: settings));
    expect(calls, 1);
    await settings.setWeekStart(DateTime.monday);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(ranges[0], isNot(ranges[1]));

    first.complete([
      Task(
        id: 'stale',
        projectId: 'inbox',
        title: 'کار قدیمی',
        due: TaskDue.onDay(DateTime(2026, 11, 23)),
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('کار قدیمی'), findsNothing);
  });

  testWidgets('month shows retry after loading error', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app((from, to) async {
        if (++calls == 1) throw StateError('offline');
        return [];
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('دریافت کارهای تقویم ممکن نشد.'), findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('برای این روز کاری زمان‌بندی نشده است.'), findsOneWidget);
  });
  testWidgets('adjacent Gregorian day reloads without extra same-month fetch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(
      app((from, to) async {
        calls++;
        if (calls == 1) return [];
        return [
          Task(
            id: 'dec-task',
            projectId: 'inbox',
            title: 'کار ماه جدید',
            due: TaskDue.onDay(DateTime(2026, 12, 1)),
          ),
        ];
      }, settings: CalendarSettings(system: CalendarSystem.gregorian)),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byKey(const ValueKey('month-day-2026-11-24')));
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byKey(const ValueKey('month-day-2026-12-1')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('کار ماه جدید'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjacent Jalali day loads its own month tasks', (tester) async {
    final settings = CalendarSettings();
    final month = monthContaining(DateTime(2026, 11, 23), settings);
    final adjacent = month.days.firstWhere(
      (day) => day.isBefore(month.firstDay) || day.isAfter(month.lastDay),
    );
    var calls = 0;
    await tester.pumpWidget(
      app((from, to) async {
        calls++;
        if (calls == 1) return [];
        return [
          Task(
            id: 'adjacent',
            projectId: 'inbox',
            title: 'کار روز کناری',
            due: TaskDue.onDay(adjacent),
          ),
        ];
      }, settings: settings),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(
      find.byKey(
        ValueKey(
          'month-day-${adjacent.year}-${adjacent.month}-${adjacent.day}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('کار روز کناری'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
