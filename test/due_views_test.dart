import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';

import 'support/fake_tasks_api.dart';

const _inbox = Project(
  id: 'inbox',
  name: 'Inbox',
  isInbox: true,
  color: '#0F8B7C',
);
const _work = Project(id: 'work', name: 'کار', color: '#2563eb');
const _old = Project(id: 'old', name: 'Old', color: '#16a34a');

void main() {
  final today = dayOf(DateTime.now());
  DateTime day(int offset) => today.add(Duration(days: offset));
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
    for (final hidden in ['Tomorrow', 'Undated', 'Done', 'Archived']) {
      expect(find.text(hidden), findsNothing);
    }
    // Each task names its project; tapping opens it there.
    expect(find.text('کار'), findsOneWidget);
    await tester.tap(find.text('Now'));
    expect(opened.single.id, 'work');

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
