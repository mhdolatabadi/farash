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
}
