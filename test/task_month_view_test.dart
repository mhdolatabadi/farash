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
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
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

  testWidgets('tapping a neighboring month day loads its month', (
    tester,
  ) async {
    final settings = CalendarSettings();
    final current = monthContaining(DateTime(2026, 11, 23), settings);
    final neighbor = current.gridStart.isBefore(current.firstDay)
        ? current.gridStart
        : current.gridEnd;
    final nextMonth = monthContaining(neighbor, settings);
    expect(nextMonth.firstDay, isNot(current.firstDay));
    final loads = <DateTime>[];

    await tester.pumpWidget(
      app((from, to) async {
        loads.add(from);
        return [
          Task(
            id: 'neighbor',
            projectId: 'inbox',
            title: 'کار ماه همسایه',
            due: TaskDue.onDay(neighbor),
          ),
        ];
      }, settings: settings),
    );
    await tester.pumpAndSettle();

    final day = find.byKey(
      ValueKey('month-day-${neighbor.year}-${neighbor.month}-${neighbor.day}'),
    );
    await tester.ensureVisible(day);
    await tester.tap(day);
    await tester.pumpAndSettle();

    expect(loads, hasLength(2));
    expect(loads.last, nextMonth.gridStart);
    expect(find.text('کار ماه همسایه'), findsOneWidget);
  });

  testWidgets('today remains distinguishable on a narrow RTL phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app((from, to) async => []));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('month-day-2026-11-23')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains('امروز') == true &&
            widget.properties.selected == true,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
