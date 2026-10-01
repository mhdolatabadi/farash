import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

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

  testWidgets('sections show their tasks under a header with a count', (
    tester,
  ) async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    tasksApi.seed('p1', 'Loose');
    tasksApi.seed('p1', 'Planned', sectionId: backlog.id);
    await pumpView(tester);

    final header = find.byKey(ValueKey('section-${backlog.id}'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.textContaining('Backlog')),
      findsOneWidget,
    );
    // The loose task comes before the header, the planned one after it.
    expect(
      tester.getTopLeft(find.text('Loose')).dy,
      lessThan(tester.getTopLeft(header).dy),
    );
    expect(
      tester.getTopLeft(find.text('Planned')).dy,
      greaterThan(tester.getTopLeft(header).dy),
    );
  });

  testWidgets('adds a section and a task into it', (tester) async {
    await pumpView(tester);

    await tester.tap(find.text('افزودن بخش'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'هفته بعد');
    await tester.tap(find.text('افزودن').last);
    await tester.pumpAndSettle();

    final section = sectionsApi.byName('هفته بعد');
    await tester.tap(find.byTooltip('افزودن کار به «هفته بعد»'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'خرید بلیت');
    await tester.tap(find.text('افزودن').last);
    await tester.pumpAndSettle();

    expect(find.text('خرید بلیت'), findsOneWidget);
    expect(tasksApi.byTitle('خرید بلیت').sectionId, section.id);
  });

  testWidgets('collapsing hides a section\'s tasks', (tester) async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    tasksApi.seed('p1', 'Planned', sectionId: backlog.id);
    await pumpView(tester);

    await tester.tap(find.byTooltip('بستن بخش'));
    await tester.pumpAndSettle();

    expect(find.text('Planned'), findsNothing);
    expect(sectionsApi.byName('Backlog').isCollapsed, isTrue);

    await tester.tap(find.byTooltip('باز کردن بخش'));
    await tester.pumpAndSettle();
    expect(find.text('Planned'), findsOneWidget);
  });

  testWidgets('deleting a section can keep its tasks', (tester) async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    tasksApi.seed('p1', 'Planned', sectionId: backlog.id);
    await pumpView(tester);

    await tester.tap(find.byTooltip('گزینه‌های بخش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف بخش'));
    await tester.pumpAndSettle();
    expect(find.text('حذف بخش «Backlog»؟'), findsOneWidget);
    await tester.tap(find.text('حذف و نگه‌داشتن کارها'));
    await tester.pumpAndSettle();

    expect(sectionsApi.all, isEmpty);
    expect(find.text('Planned'), findsOneWidget);
    expect(tasksApi.byTitle('Planned').sectionId, isNull);
  });

  testWidgets('dragging a task under another header moves it there', (
    tester,
  ) async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    final loose = tasksApi.seed('p1', 'Loose');
    tasksApi.seed('p1', 'Planned', sectionId: backlog.id);
    await pumpView(tester);

    final handle = find.descendant(
      of: find.byKey(ValueKey(loose.id)),
      matching: find.byIcon(Icons.drag_indicator),
    );
    final target = tester.getCenter(find.text('Planned'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(target + const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tasksApi.byTitle('Loose').sectionId, backlog.id);
    expect(tasksApi.reorders.last.$2, contains(loose.id));
  });

  testWidgets('the detail sheet moves a task into a section', (tester) async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    tasksApi.seed('p1', 'Loose');
    await pumpView(tester);

    await tester.tap(find.text('Loose'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backlog').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(tasksApi.byTitle('Loose').sectionId, backlog.id);
  });

  testWidgets('long section names do not overflow a narrow screen', (
    tester,
  ) async {
    sectionsApi.seed(
      'p1',
      'بخشی با نامی بسیار طولانی که در یک خط جا نمی‌شود و باید کوتاه شود تا چیزی بیرون نزند',
    );
    await pumpView(tester, size: const Size(320, 640));

    expect(tester.takeException(), isNull);
  });
}
