import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  test(
    'migrate the former garden preference without changing task views',
    () async {
      final store = MemoryCalendarSettingsStore()
        ..values['start_view'] = 'garden';
      final start = StartView(store: store);
      await start.load();
      expect(start.value, StartView.weaving);
      expect(StartView(value: 'garden').value, StartView.weaving);
      await start.set('today');
      expect(start.value, 'today');
      expect(store.values['start_view'], 'today');
    },
  );

  Future<FakeTasksApi> pumpHome(
    WidgetTester tester,
    StartView start, {
    void Function(FakeTasksApi)? seed,
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = FakeTasksApi();
    seed?.call(tasks);
    final projects = ProjectsController(
      api: FakeProjectsApi(),
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
            token: () => 'token',
            startView: start,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tasks;
  }

  testWidgets('the saved start view opens first and can be changed', (
    tester,
  ) async {
    final store = MemoryCalendarSettingsStore()..values['start_view'] = 'week';
    final start = StartView(store: store);
    await pumpHome(tester, start);
    await start.load();
    await tester.pumpAndSettle();
    expect(find.byType(DueTasksView), findsOneWidget);
    expect(find.text('۷ روز آینده'), findsWidgets);

    await tester.tap(find.byTooltip('حساب و تنظیمات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('صفحهٔ آغاز'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'امروز'));
    await tester.pumpAndSettle();
    expect(store.values['start_view'], 'today');
  });

  testWidgets('today shows its count of due and late tasks', (tester) async {
    final today = dayOf(DateTime.now());
    await pumpHome(
      tester,
      StartView(),
      seed: (api) {
        api.seed('inbox', 'A', dates: TaskDates(due: TaskDue.onDay(today)));
        api.seed(
          'inbox',
          'B',
          dates: TaskDates(
            due: TaskDue.onDay(today.subtract(const Duration(days: 2))),
          ),
        );
        api.seed(
          'inbox',
          'C',
          dates: TaskDates(
            due: TaskDue.onDay(today.add(const Duration(days: 1))),
          ),
        );
      },
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('view-today')),
        matching: find.text('۲'),
      ),
      findsOneWidget,
    );
  });
}
