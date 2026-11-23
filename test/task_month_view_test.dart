import 'dart:async';

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

  testWidgets('changing account loader clears tasks and ignores stale results', (
    tester,
  ) async {
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
}
