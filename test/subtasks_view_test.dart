import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

void main() {
  late FakeTasksApi tasksApi;
  late FakeSectionsApi sectionsApi;

  setUp(() {
    tasksApi = FakeTasksApi();
    sectionsApi = FakeSectionsApi(tasks: tasksApi);
  });

  Future<void> pumpView(
    WidgetTester tester, {
    Size size = const Size(420, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProjectTasksView(
              project: _work,
              api: tasksApi,
              sectionsApi: sectionsApi,
              token: () => 'token',
              moveTargets: () => const [_work],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TaskTile tileOf(WidgetTester tester, String id) => tester.widget<TaskTile>(
    find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byType(TaskTile),
    ),
  );

  testWidgets('subtasks are indented under their parent with progress', (
    tester,
  ) async {
    final trip = tasksApi.seed('p1', 'Trip');
    final tickets = tasksApi.seed('p1', 'Tickets', parent: trip);
    tasksApi.seed('p1', 'Hotel', parent: trip, completed: true);
    await pumpView(tester);

    expect(tileOf(tester, tickets.id).depth, 1);
    expect(
      tester.getTopLeft(find.text('Tickets')).dy,
      greaterThan(tester.getTopLeft(find.text('Trip')).dy),
    );
    expect(find.text('۱/۲'), findsOneWidget);

    await tester.tap(find.byTooltip('پنهان کردن زیرکارها'));
    await tester.pumpAndSettle();
    expect(find.text('Tickets'), findsNothing);
    await tester.tap(find.byTooltip('نمایش زیرکارها'));
    await tester.pumpAndSettle();
    expect(find.text('Tickets'), findsOneWidget);
  });

  testWidgets('dropping a task under a parent\'s first subtask nests it', (
    tester,
  ) async {
    final trip = tasksApi.seed('p1', 'Trip');
    tasksApi.seed('p1', 'Tickets', parent: trip);
    final loose = tasksApi.seed('p1', 'Loose');
    await pumpView(tester);

    // Drag Loose up to sit between Trip and Tickets.
    final handle = find.descendant(
      of: find.byKey(ValueKey(loose.id)),
      matching: find.byIcon(Icons.drag_indicator),
    );
    final start = tester.getCenter(handle);
    final tickets = tester.getRect(find.text('Tickets'));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 50));
    // Up in steps until the dragged row sits just above Tickets.
    final goal = tickets.top - 4;
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(
        Offset(start.dx, start.dy + (goal - start.dy) * i / 10),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tasksApi.byTitle('Loose').parentId, trip.id);
    expect(tileOf(tester, loose.id).depth, 1);
  });

  testWidgets('the detail sheet adds subtasks and indents', (tester) async {
    tasksApi.seed('p1', 'A');
    final b = tasksApi.seed('p1', 'B');
    await pumpView(tester);

    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'زیرکار تازه'), 'B1');
    await tester.tap(find.byTooltip('افزودن زیرکار'));
    await tester.pumpAndSettle();
    expect(tasksApi.byTitle('B1').parentId, b.id);
    expect(find.text('زیرکارها ۰/۱'), findsOneWidget);

    await tester.ensureVisible(find.text('زیرکارِ کار بالایی'));
    await tester.tap(find.text('زیرکارِ کار بالایی'));
    await tester.pumpAndSettle();
    expect(tasksApi.byTitle('B').parentId, tasksApi.byTitle('A').id);
    expect(find.text('زیرکارِ «A»'), findsOneWidget);
  });

  testWidgets('checklist items tick and save from the sheet', (tester) async {
    final task = tasksApi.seed('p1', 'خرید');
    await tasksApi.updateTask(
      'token',
      task.id,
      const TaskDraft(description: 'نکته\n- [ ] نان'),
    );
    await pumpView(tester);
    expect(find.text('۰/۱'), findsOneWidget);

    await tester.tap(find.text('خرید'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'نان'));
    await tester.pumpAndSettle();
    expect(tasksApi.byTitle('خرید').description, 'نکته\n- [x] نان');

    await tester.enterText(
      find.widgetWithText(TextField, 'مورد تازهٔ چک‌لیست'),
      'شیر',
    );
    await tester.tap(find.byTooltip('افزودن به چک‌لیست'));
    await tester.pumpAndSettle();
    expect(tasksApi.byTitle('خرید').description, 'نکته\n- [x] نان\n- [ ] شیر');
  });

  testWidgets('deep subtasks with long text fit a narrow screen', (
    tester,
  ) async {
    var parent = tasksApi.seed(
      'p1',
      'کاری با عنوانی بسیار طولانی که باید در صفحهٔ باریک بشکند و بیرون نزند',
    );
    for (var i = 0; i < 4; i++) {
      parent = tasksApi.seed(
        'p1',
        'زیرکاری با عنوان طولانی در سطح ${i + 2} که نباید از صفحه بیرون بزند',
        parent: parent,
      );
    }
    await pumpView(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.byKey(ValueKey(parent.id)),
      find.byType(CustomScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tileOf(tester, parent.id).depth, 4);
    // The deepest row still leaves its title room beside the controls.
    expect(
      tester.getSize(find.text(tasksApi.byTitle(parent.title).title)).width,
      greaterThan(100),
    );
  });
}
