import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');
const _home = Project(id: 'p2', name: 'خانه', color: '#16a34a');

void main() {
  late FakeTasksApi api;

  Future<void> pumpView(
    WidgetTester tester, {
    Project project = _work,
    Size size = const Size(400, 800),
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
              project: project,
              api: api,
              token: () => 'token',
              moveTargets: () => const [_work, _home],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => api = FakeTasksApi());

  testWidgets('quick add needs one field and one action', (tester) async {
    await pumpView(tester);

    expect(find.text('هنوز کاری در «کار» نیست.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'خرید نان');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('خرید نان'), findsOneWidget);
    expect(api.byTitle('خرید نان').projectId, 'p1');
    // The field is cleared for the next task.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('quick add can set a priority', (tester) async {
    await pumpView(tester);

    await tester.tap(find.byTooltip('اولویت: اولویت ۴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اولویت ۱').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Urgent');
    await tester.tap(find.byTooltip('افزودن کار'));
    await tester.pumpAndSettle();

    expect(api.byTitle('Urgent').priority, TaskPriority.p1);
  });

  testWidgets('completing offers undo', (tester) async {
    api.seed('p1', 'A');
    await pumpView(tester);

    await tester.tap(find.bySemanticsLabel('انجام «A»'));
    await tester.pumpAndSettle();

    expect(find.text('«A» انجام شد.'), findsOneWidget);
    expect(api.byTitle('A').isCompleted, isTrue);

    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();

    expect(api.byTitle('A').isCompleted, isFalse);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('show completed lists done tasks under a heading', (
    tester,
  ) async {
    api.seed('p1', 'Open');
    api.seed('p1', 'Done', completed: true);
    await pumpView(tester);

    expect(find.text('Done'), findsNothing);

    await tester.tap(find.text('نمایش انجام‌شده‌ها'));
    await tester.pumpAndSettle();

    expect(find.text('انجام‌شده'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('the detail sheet edits, moves and deletes with undo', (
    tester,
  ) async {
    api.seed('p1', 'A');
    api.seed('p1', 'B');
    await pumpView(tester);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'عنوان'), 'A2');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'توضیحات'),
      'جزئیات',
    );
    await tester.tap(find.text('اولویت ۲'));
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(find.text('A2'), findsOneWidget);
    expect(api.byTitle('A2').description, 'جزئیات');
    expect(api.byTitle('A2').priority, TaskPriority.p2);

    // Move B to «خانه».
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('خانه').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ذخیره'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();

    expect(find.text('B'), findsNothing);
    expect(api.byTitle('B').projectId, 'p2');

    // Delete A2, then undo.
    await tester.tap(find.text('A2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();

    expect(find.text('A2'), findsNothing);
    expect(find.text('«A2» حذف شد.'), findsOneWidget);

    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('a folder explains that it holds projects only', (tester) async {
    await pumpView(
      tester,
      project: const Project(
        id: 'f1',
        name: 'Folder',
        color: '#2563eb',
        kind: ProjectKind.folder,
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('پوشه فقط پروژه نگه می‌دارد'), findsOneWidget);
  });

  testWidgets('a narrow screen with the keyboard keeps the last task visible', (
    tester,
  ) async {
    for (var i = 0; i < 12; i++) {
      api.seed('p1', 'کار شمارهٔ $i با عنوانی بلند که باید در دو خط بشکند');
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    await pumpView(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);

    // Scroll to the very end: the last task must sit fully above the
    // quick-add bar, not behind it.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -5000),
      3000,
    );
    await tester.pumpAndSettle();
    final last = find.textContaining('کار شمارهٔ 11');
    final lastBottom = tester.getBottomLeft(last).dy;
    final quickAddTop = tester.getTopLeft(find.byType(TextField)).dy;
    expect(lastBottom, lessThanOrEqualTo(quickAddTop));
  });
}
