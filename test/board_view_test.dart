import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/board_view.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

void main() {
  late FakeTasksApi tasks;
  late FakeSectionsApi sections;
  late MemoryCalendarSettingsStore store;

  setUp(() {
    tasks = FakeTasksApi();
    sections = FakeSectionsApi(tasks: tasks);
    store = MemoryCalendarSettingsStore();
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProjectTasksView(
              key: UniqueKey(),
              project: _work,
              api: tasks,
              sectionsApi: sections,
              token: () => 'token',
              moveTargets: () => const [_work],
              layouts: ProjectLayouts(store: store),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inColumn(String column, String text) => find.descendant(
    of: find.byKey(ValueKey('column-$column')),
    matching: find.text(text),
  );

  testWidgets('the board is remembered per project and drags cards across', (
    tester,
  ) async {
    final doing = sections.seed('p1', 'در جریان');
    tasks.seed('p1', 'نوشتن گزارش');
    tasks.seed('p1', 'تماس با بانک');
    await pump(tester, const Size(1000, 800));

    await tester.tap(find.byKey(const ValueKey('layout-toggle')));
    await tester.pumpAndSettle();
    expect(store.values['project_layout_p1'], 'board');
    expect(inColumn('none', 'نوشتن گزارش'), findsOneWidget);
    expect(inColumn(doing.id, 'در جریان'), findsOneWidget);
    expect(find.text('افزودن ستون'), findsOneWidget);

    final start = tester.getCenter(inColumn('none', 'نوشتن گزارش'));
    final end = tester.getCenter(find.byKey(ValueKey('column-${doing.id}')));
    // Touch picks a card up with a long press, leaving swipes to scroll.
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(inColumn(doing.id, 'نوشتن گزارش'), findsOneWidget);
    expect(
      tasks.all.firstWhere((t) => t.title == 'نوشتن گزارش').sectionId,
      doing.id,
    );

    // Opening the project again comes back to the board.
    await pump(tester, const Size(1000, 800));
    expect(find.byKey(ValueKey('column-${doing.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones page one column at a time without overflow', (
    tester,
  ) async {
    store.values['project_layout_p1'] = 'board';
    sections.seed('p1', 'بخشی با نامی بسیار طولانی برای آزمودن صفحهٔ باریک');
    for (var i = 0; i < 8; i++) {
      tasks.seed('p1', 'کاری با عنوانی طولانی که باید درست بشکند $i');
    }
    await pump(tester, const Size(360, 740));
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byKey(const ValueKey('column-none')), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
