import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_tasks_api.dart';
import 'support/fake_sections_api.dart';

const _inbox = Project(
  id: 'inbox',
  name: 'Inbox',
  isInbox: true,
  color: '#0F8B7C',
);
const _work = Project(id: 'work', name: 'کار', color: '#2563eb');
const _old = Project(id: 'old', name: 'Old', color: '#16a34a');

class _DelayedTaskContext extends FakeTasksApi {
  final ready = Completer<void>();
  int loads = 0;
  bool? requestedCompleted;

  @override
  Future<List<Task>> listTasks(
    String token,
    String projectId, {
    bool showCompleted = false,
  }) async {
    loads++;
    requestedCompleted = showCompleted;
    await ready.future;
    return super.listTasks(token, projectId, showCompleted: showCompleted);
  }
}

class _RecurringTodayApi extends FakeTasksApi implements TimeApi {
  bool failRule = true;
  final paths = <String>[];
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    paths.add(path);
    if (failRule) throw StateError('response lost');
    return {
      'recurrence': {'schedule': body!['schedule'], 'emitted': 0},
    };
  }
}

void main() {
  final today = dayOf(DateTime.now());
  // Calendar days, not 24-hour steps, so offsets stay exact across DST.
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset);
  TaskDates on(int offset) => TaskDates(due: TaskDue.onDay(day(offset)));
  late FakeTasksApi api;
  late List<Project> opened;

  setUp(() {
    api = FakeTasksApi();
    opened = [];
  });

  Future<void> pump(WidgetTester tester, DueView view) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            CalendarScope(settings: CalendarSettings(), child: child!),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: DueTasksView(
              view: view,
              api: api,
              token: () => 'token',
              projects: () => const [_inbox, _work, _old],
              onOpenProject: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('agenda keeps distinct days across the autumn clock change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api.seed(
      'work',
      'After change',
      dates: TaskDates(due: TaskDue.onDay(DateTime(2026, 10, 25))),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: DueTasksView(
              view: DueView.upcoming,
              api: api,
              token: () => 'token',
              projects: () => const [_work],
              onOpenProject: (_) {},
              now: () => DateTime(2026, 10, 20),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('After change'), 200);
    expect(find.text('After change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Today retries failed task context without opening a stale editor',
    (tester) async {
      api.seed('work', 'Now', dates: on(0));
      await pump(tester, DueView.today);
      api.failNext = StateError('context unavailable');
      await tester.tap(find.text('Now'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailEditor), findsNothing);
      expect(
        find.text('جزئیات کار دریافت نشد؛ دوباره تلاش کنید.'),
        findsOneWidget,
      );
      await tester.tap(find.text('تلاش دوباره'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Today refuses to edit a task removed since its list loaded', (
    tester,
  ) async {
    final task = api.seed('work', 'Removed', dates: on(0));
    await pump(tester, DueView.today);
    await api.deleteTask('token', task.id);
    await tester.tap(find.text('Removed'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsNothing);
    expect(find.text('تلاش دوباره'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today opens one editor after loading complete task context', (
    tester,
  ) async {
    final delayed = _DelayedTaskContext();
    api = delayed;
    api.seed('work', 'Now', dates: on(0));
    await pump(tester, DueView.today);
    await tester.tap(find.text('Now'));
    await tester.pump();
    await tester.tap(find.text('Now'));
    await tester.pump();
    expect(delayed.loads, 1);
    expect(find.byType(TaskDetailEditor), findsNothing);
    delayed.ready.complete();
    await tester.pumpAndSettle();
    expect(delayed.requestedCompleted, isTrue);
    expect(find.byType(TaskDetailEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today adds to the Inbox for today', (tester) async {
    await pump(tester, DueView.today);
    await tester.enterText(find.byType(TextField), 'خرید نان');
    await tester.pump();
    await tester.tap(find.byTooltip('افزودن کار'));
    await tester.pumpAndSettle();
    final added = api.byTitle('خرید نان');
    expect(added.projectId, 'inbox');
    expect(added.due, TaskDue.onDay(today));
    expect(find.text('خرید نان'), findsOneWidget);
  });

  testWidgets('Today resolves project and section before creating', (
    tester,
  ) async {
    final sections = FakeSectionsApi()..seed('work', 'برنامه');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DueTasksView(
            view: DueView.today,
            api: api,
            token: () => 'token',
            projects: () => const [_inbox, _work],
            onOpenProject: (_) {},
            sectionsApi: sections,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'مطالعه #کار /برنامه');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('افزودن کار'));
    await tester.pumpAndSettle();
    expect(api.all.single.projectId, 'work');
    expect(api.all.single.sectionId, sections.all.single.id);
    expect(api.all.single.due!.day, today);
    expect(api.all.single.title, 'مطالعه');
  });

  testWidgets('Today refuses unknown projects instead of Inbox fallback', (
    tester,
  ) async {
    await pump(tester, DueView.today);
    await tester.enterText(find.byType(TextField), 'مطالعه #گم‌شده');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('افزودن کار'));
    await tester.pumpAndSettle();
    expect(api.all, isEmpty);
    expect(find.textContaining('پروژه پیدا نشد'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'مطالعه #گم‌شده',
    );
  });

  testWidgets(
    'Today narrow dark large text retries only confirmed recurrence',
    (tester) async {
      final recurring = _RecurringTodayApi();
      debugTimeZoneOverride = 'Asia/Tehran';
      addTearDown(() => debugTimeZoneOverride = null);
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: FarashTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DueTasksView(
                view: DueView.today,
                api: recurring,
                token: () => 'token',
                projects: () => const [_inbox],
                onOpenProject: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'مطالعه هر روز');
      await tester.pumpAndSettle();
      final send = find.byTooltip('افزودن کار');
      expect(tester.getRect(send).bottom, lessThanOrEqualTo(510));
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(recurring.all, hasLength(1));
      final id = recurring.all.single.id;
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        find.textContaining('کار ساخته شد اما تکرارش ذخیره نشد'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      recurring.failRule = false;
      final retry = find.byTooltip('ذخیرهٔ تکرار کار ساخته‌شده');
      expect(tester.getRect(retry).bottom, lessThanOrEqualTo(510));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(recurring.all, hasLength(1));
      expect(recurring.paths, [
        '/api/v1/tasks/$id/recurrence',
        '/api/v1/tasks/$id/recurrence',
      ]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing the editor asks before dropping edits', (tester) async {
    api.seed('work', 'Now', dates: on(0));
    await pump(tester, DueView.today);
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Later');
    await tester.tap(find.byTooltip('بستن ویرایشگر'));
    await tester.pumpAndSettle();
    expect(find.text('تغییرها ذخیره نشده‌اند'), findsOneWidget);
    await tester.tap(find.text('ادامهٔ ویرایش'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsOneWidget);
    await tester.tap(find.byTooltip('بستن ویرایشگر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دور ریختن'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsNothing);
    expect(api.byTitle('Now').title, 'Now');
  });

  testWidgets('today gathers late and due tasks from every project', (
    tester,
  ) async {
    api.seed('inbox', 'Late', dates: on(-2));
    api.seed('work', 'Now', dates: on(0));
    api.seed('work', 'Tomorrow', dates: on(1));
    api.seed('work', 'Undated');
    api.seed('work', 'Done', dates: on(0), completed: true);
    api.seed('old', 'Archived', dates: on(0));
    api.archivedProjects.add('old');
    await pump(tester, DueView.today);

    expect(find.text('دیرشده'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    // Under the «امروز» heading the rows don't repeat «امروز».
    expect(
      find.descendant(of: find.byType(TaskTile), matching: find.text('امروز')),
      findsNothing,
    );
    for (final hidden in ['Tomorrow', 'Undated', 'Done', 'Archived']) {
      expect(find.text(hidden), findsNothing);
    }
    // Each task names its project; tapping opens it in the editor here.
    expect(find.text('کار'), findsOneWidget);
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsOneWidget);
    expect(opened, isEmpty);
    await tester.tap(find.byTooltip('بستن ویرایشگر'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsNothing);

    // Late tasks move to today together, and come back with undo.
    await tester.tap(find.text('انتقال همه به امروز'));
    await tester.pumpAndSettle();
    expect(find.text('دیرشده'), findsNothing);
    expect(api.byTitle('Late').due, TaskDue.onDay(today));
    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();
    expect(api.byTitle('Late').due, TaskDue.onDay(day(-2)));
    expect(find.text('دیرشده'), findsOneWidget);
  });

  testWidgets('checking a task off in today completes it with undo', (
    tester,
  ) async {
    api.seed('work', 'Now', dates: on(0));
    await pump(tester, DueView.today);
    await tester.tap(find.bySemanticsLabel('انجام «Now»'));
    await tester.pumpAndSettle();
    expect(find.text('Now'), findsNothing);
    expect(api.byTitle('Now').isCompleted, isTrue);
    expect(find.text('برای امروز کاری نمانده.'), findsOneWidget);
    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();
    expect(find.text('Now'), findsOneWidget);
  });

  testWidgets('upcoming lists the next two weeks by day under a week strip', (
    tester,
  ) async {
    api.seed('work', 'Tomorrow', dates: on(1));
    api.seed('work', 'Later', dates: on(10));
    api.seed('work', 'Too far', dates: on(upcomingDays + 1));
    api.seed('work', 'Today', dates: on(0));
    await pump(tester, DueView.upcoming);

    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('فردا'), findsWidgets);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Too far', skipOffstage: false), findsNothing);
    expect(find.text('Later'), findsNothing); // below the fold

    // A day in the strip scrolls the agenda there.
    final settings = CalendarSettings();
    await tester.tap(
      find.byTooltip(
        formatDate(day(7), settings, today: today, withWeekday: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
    await tester.scrollUntilVisible(find.text('Later'), 200);
    expect(find.text('Later'), findsOneWidget);
  });

  testWidgets('the week view shows today and the next six days', (
    tester,
  ) async {
    api.seed('work', 'Late', dates: on(-1));
    api.seed('work', 'Today', dates: on(0));
    api.seed('work', 'Sixth', dates: on(6));
    api.seed('work', 'Eighth', dates: on(7));
    await pump(tester, DueView.week);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Late'), findsNothing);
    await tester.scrollUntilVisible(find.text('Sixth'), 200);
    expect(find.text('Eighth', skipOffstage: false), findsNothing);
  });

  testWidgets('all shows every dated task, late ones first', (tester) async {
    api.seed('work', 'Late', dates: on(-3));
    api.seed('work', 'Far', dates: on(200));
    api.seed('work', 'Undated');
    await pump(tester, DueView.all);
    expect(find.text('دیرشده'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.text('Far'), findsOneWidget);
    expect(find.text('Undated'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Late')).dy,
      lessThan(tester.getTopLeft(find.text('Far')).dy),
    );
  });

  testWidgets('dragging a task onto a day moves it, with undo', (tester) async {
    api.seed('work', 'Tomorrow', dates: on(1));
    await pump(tester, DueView.upcoming);
    final settings = CalendarSettings();
    final target = find.byTooltip(
      formatDate(day(3), settings, today: today, withWeekday: true),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tomorrow')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(api.byTitle('Tomorrow').due, TaskDue.onDay(day(3)));
    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();
    expect(api.byTitle('Tomorrow').due, TaskDue.onDay(day(1)));
  });

  testWidgets('a task can change day without dragging', (tester) async {
    api.seed('work', 'Tomorrow', dates: on(1));
    await pump(tester, DueView.upcoming);
    await tester.tap(find.byTooltip('تغییر روز «Tomorrow»'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('امروز').last);
    await tester.tap(find.text('تأیید'));
    await tester.pumpAndSettle();
    expect(api.byTitle('Tomorrow').due, TaskDue.onDay(today));
  });
}
