import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

void main() {
  late FakeTasksApi api;
  final today = dayOf(DateTime.now());
  final tomorrow = today.add(const Duration(days: 1));

  setUp(() {
    api = FakeTasksApi();
    debugTimeZoneOverride = 'Asia/Tehran';
  });
  tearDown(() => debugTimeZoneOverride = null);

  group('model', () {
    test('a due reads and writes the API JSON', () {
      final timed = TaskDue.fromJson({
        'date': '2026-10-06',
        'datetime': '2026-10-05T21:00:00Z',
        'timezone': 'Asia/Tehran',
      });
      expect(timed.isTimed, isTrue);
      expect(timed.toJson(), {
        'datetime': '2026-10-05T21:00:00.000Z',
        'timezone': 'Asia/Tehran',
      });
      final allDay = TaskDue.onDay(DateTime(2026, 10, 6));
      expect(allDay.toJson(), {'date': '2026-10-06'});
      expect(allDay.day, DateTime(2026, 10, 6));
      expect(allDay.isOverdue(DateTime(2026, 10, 6, 23)), isFalse);
      expect(allDay.isOverdue(DateTime(2026, 10, 7)), isTrue);
    });

    test('dates send every field so the API can clear them', () {
      expect(const TaskDates().toJson(), {
        'due': null,
        'deadline': null,
        'duration_minutes': null,
      });
      // A duration only travels with a timed due.
      expect(
        TaskDates(
          due: TaskDue.onDay(DateTime(2026, 10, 6)),
          durationMinutes: 30,
        ).toJson()['duration_minutes'],
        isNull,
      );
      final task = Task.fromJson({
        'id': 't1',
        'project_id': 'p1',
        'title': 'x',
        'due': {'date': '2026-10-06', 'datetime': null, 'timezone': null},
        'deadline': '2026-10-10',
        'duration_minutes': null,
      });
      expect(task.due!.date, '2026-10-06');
      expect(task.deadline, '2026-10-10');
    });

    test('the client posts a bulk reschedule', () async {
      late http.Request sent;
      final client = ApiClient(
        Uri.parse('https://todo.example.com'),
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'tasks': [
                {
                  'id': 't1',
                  'project_id': 'p1',
                  'title': 'x',
                  'due': {'date': '2026-10-09'},
                },
              ],
            }),
            200,
          );
        }),
      );
      final tasks = await client.rescheduleTasks('token', [
        't1',
      ], TaskDue.onDay(DateTime(2026, 10, 9)));
      expect(sent.url.path, '/api/v1/tasks/reschedule');
      expect(jsonDecode(sent.body), {
        'task_ids': ['t1'],
        'due': {'date': '2026-10-09'},
      });
      expect(tasks.single.due!.date, '2026-10-09');
    });
  });

  group('controller', () {
    late TasksController tasks;
    setUp(() {
      tasks = TasksController(api: api, token: () => 'token', projectId: 'p1');
    });

    test('editing saves due, deadline and duration', () async {
      final a = api.seed('p1', 'A');
      await tasks.load();
      final due = TaskDue.at(DateTime(2026, 10, 6, 14, 30), 'Asia/Tehran');
      await tasks.edit(
        a,
        title: 'A',
        description: '',
        priority: TaskPriority.p4,
        projectId: 'p1',
        dates: TaskDates(due: due, deadline: '2026-10-10', durationMinutes: 45),
      );
      final saved = api.byTitle('A');
      expect(saved.due, due);
      expect(saved.deadline, '2026-10-10');
      expect(saved.durationMinutes, 45);
    });

    test('reschedule moves many tasks and keeps their deadlines', () async {
      final a = api.seed(
        'p1',
        'A',
        dates: const TaskDates(deadline: '2026-11-01'),
      );
      final b = api.seed('p1', 'B');
      await tasks.load();
      final due = TaskDue.onDay(DateTime(2026, 10, 9));

      await tasks.reschedule([a, b], due);

      expect(api.reschedules.single.$1, [a.id, b.id]);
      expect(api.byTitle('A').due, due);
      expect(api.byTitle('A').deadline, '2026-11-01');
      expect(tasks.taskById(b.id)!.due, due);
    });

    test('a refused reschedule rolls back', () async {
      final a = api.seed('p1', 'A');
      await tasks.load();
      api.failNext = const ApiException('offline');
      await expectLater(
        tasks.reschedule([a], TaskDue.onDay(DateTime(2026, 10, 9))),
        throwsA(isA<ApiException>()),
      );
      expect(tasks.taskById(a.id)!.due, isNull);
    });
  });

  group('screens', () {
    Future<void> pumpView(
      WidgetTester tester, {
      CalendarSettings? settings,
      Size size = const Size(420, 900),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          // Above the navigator, as in the app, so sheets see it too.
          builder: (context, child) => CalendarScope(
            settings: settings ?? CalendarSettings(),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ProjectTasksView(
                project: _work,
                api: api,
                sectionsApi: FakeSectionsApi(tasks: api),
                token: () => 'token',
                moveTargets: () => const [_work],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Color colorOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('rows show the due day; overdue reads in red', (tester) async {
      api.seed('p1', 'Soon', dates: TaskDates(due: TaskDue.onDay(tomorrow)));
      api.seed(
        'p1',
        'Late',
        dates: TaskDates(
          due: TaskDue.onDay(today.subtract(const Duration(days: 3))),
          deadline: dateKey(today.subtract(const Duration(days: 1))),
        ),
      );
      await pumpView(tester);
      final theme = Theme.of(tester.element(find.text('Soon')));

      expect(find.text('فردا'), findsOneWidget);
      expect(colorOf(tester, 'فردا'), isNot(theme.colorScheme.error));
      final late = formatDate(
        today.subtract(const Duration(days: 3)),
        CalendarSettings(),
      );
      expect(colorOf(tester, late), theme.colorScheme.error);
      expect(find.bySemanticsLabel(RegExp('دیرشده، مهلت')), findsOneWidget);
    });

    testWidgets('the scheduler sets a due date and a deadline', (tester) async {
      api.seed('p1', 'A');
      await pumpView(tester);

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('زمان‌بندی: بدون تاریخ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فردا'));
      await tester.pump();
      await tester.tap(find.text('مهلت'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('هفتهٔ بعد'));
      await tester.pump();
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();

      final saved = api.byTitle('A');
      expect(saved.due, TaskDue.onDay(tomorrow));
      final nextWeek = startOfWeek(
        today,
        DateTime.saturday,
      ).add(const Duration(days: 7));
      expect(saved.deadline, dateKey(nextWeek));
      expect(find.text('فردا'), findsOneWidget);
    });

    testWidgets('the month grid picks a Jalali day; "no date" clears it', (
      tester,
    ) async {
      api.seed('p1', 'A', dates: TaskDates(due: TaskDue.onDay(today)));
      await pumpView(tester);

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^زمان‌بندی')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('ماه بعد'));
      await tester.pumpAndSettle();
      final j = JalaliDate.fromGregorian(today);
      final next = j.month == 12
          ? JalaliDate(j.year + 1, 1, 10)
          : JalaliDate(j.year, j.month + 1, 10);
      final day = next.toGregorian();
      await tester.tap(
        find.bySemanticsLabel(
          formatDate(
            day,
            CalendarSettings(),
            withWeekday: true,
            alwaysYear: true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.byTitle('A').due, TaskDue.onDay(day));

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^زمان‌بندی')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('بدون تاریخ'));
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.byTitle('A').due, isNull);
    });

    testWidgets('several tasks reschedule at once', (tester) async {
      final a = api.seed('p1', 'A');
      final b = api.seed('p1', 'B');
      api.seed('p1', 'C');
      await pumpView(tester);

      await tester.longPress(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(find.text('۲ کار انتخاب شد'), findsOneWidget);

      await tester.tap(find.text('تغییر تاریخ'));
      await tester.pumpAndSettle();
      expect(find.text('مهلت'), findsNothing);
      await tester.tap(find.text('امروز'));
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();

      expect(api.reschedules.single.$1, [a.id, b.id]);
      expect(api.byTitle('B').due, TaskDue.onDay(today));
      expect(api.byTitle('C').due, isNull);
      expect(find.text('تاریخ ۲ کار تغییر کرد.'), findsOneWidget);
      expect(find.byTooltip('نمایش انجام‌شده‌ها'), findsOneWidget);
    });

    testWidgets('Gregorian and a Monday week start come from settings', (
      tester,
    ) async {
      final settings = CalendarSettings(
        system: CalendarSystem.gregorian,
        weekStart: DateTime.monday,
      );
      final far = DateTime(today.year, today.month, today.day + 40);
      api.seed('p1', 'A', dates: TaskDates(due: TaskDue.onDay(far)));
      await pumpView(tester, settings: settings);

      expect(find.textContaining(gregorianMonths[far.month - 1]), findsWidgets);
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^زمان‌بندی')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('هفتهٔ بعد'));
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.byTitle('A').due!.day.weekday, DateTime.monday);
    });

    testWidgets('the scheduler and dated rows fit a narrow screen', (
      tester,
    ) async {
      api.seed(
        'p1',
        'کاری با عنوانی طولانی که باید کنار تاریخ و مهلت جا شود',
        dates: TaskDates(
          due: TaskDue.at(
            DateTime(today.year, today.month, today.day + 3, 14, 30),
            'Asia/Tehran',
          ),
          deadline: dateKey(today.add(const Duration(days: 30))),
          durationMinutes: 90,
        ),
      );
      await pumpView(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      expect(find.byType(TaskDateLabels), findsOneWidget);

      await tester.tap(find.textContaining('کاری با عنوانی'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.bySemanticsLabel(RegExp('^زمان‌بندی')));
      await tester.tap(find.bySemanticsLabel(RegExp('^زمان‌بندی')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('حذف ساعت'), findsNothing);
      expect(find.byTooltip('حذف ساعت'), findsOneWidget);
      expect(find.text('مدت'), findsOneWidget);
      // Confirm stays reachable.
      await tester.ensureVisible(find.text('تأیید'));
      await tester.tap(find.text('تأیید'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
