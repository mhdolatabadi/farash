import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_labels_api.dart';
import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  late FakeTasksApi tasks;
  late FakeLabelsApi labels;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final projects = ProjectsController(
      api: FakeProjectsApi(
        projects: const [
          Project(id: 'inbox', name: 'Inbox', isInbox: true, color: '#0F8B7C'),
          Project(id: 'work', name: 'کار', color: '#2563eb'),
        ],
      ),
      token: () => 'token',
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            CalendarScope(settings: CalendarSettings(), child: child!),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            email: 'a@example.com',
            onLogout: () {},
            projects: projects,
            tasksApi: tasks,
            labelsApi: labels,
            token: () => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    tasks = FakeTasksApi();
    labels = FakeLabelsApi(tasks: tasks);
  });

  testWidgets('a label is made, put on a task and shown on its row', (
    tester,
  ) async {
    tasks.seed('inbox', 'Call mom');
    await pumpHome(tester);

    await tester.tap(find.byTooltip('برچسب تازه').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '@تلفن');
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('@تلفن'), findsWidgets);
    // Creating opens the label's page; go back to the Inbox.
    expect(find.byType(DueTasksView), findsOneWidget);
    await tester.tap(find.text('صندوق ورودی').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Call mom'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '@تلفن'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(tasks.byTitle('Call mom').labelIds, hasLength(1));
    expect(
      find.descendant(of: find.byType(TaskTile), matching: find.text('@تلفن')),
      findsOneWidget,
    );
  });

  testWidgets('a label page lists its tasks from every project', (
    tester,
  ) async {
    final shop = labels.seed('خرید');
    tasks.seed('inbox', 'Bread', labelIds: [shop.id]);
    tasks.seed('work', 'Paper', labelIds: [shop.id]);
    tasks.seed('work', 'Report');
    await pumpHome(tester);

    await tester.tap(find.byKey(ValueKey('label-${shop.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(DueTasksView), findsOneWidget);
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets('deleting a label asks first and keeps its tasks', (
    tester,
  ) async {
    final shop = labels.seed('خرید');
    tasks.seed('inbox', 'Bread', labelIds: [shop.id]);
    await pumpHome(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('label-${shop.id}')),
        matching: find.byTooltip('گزینه‌های برچسب'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف').last);
    await tester.pumpAndSettle();
    expect(find.text('حذف @خرید؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('label-${shop.id}')), findsNothing);
    expect(tasks.byTitle('Bread').labelIds, isEmpty);
    expect(find.text('Bread'), findsOneWidget);
  });
}
