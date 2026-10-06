import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

void main() {
  late FakeTasksApi api;
  setUp(() => api = FakeTasksApi());

  Future<void> pumpView(WidgetTester tester, {bool showTitle = true}) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProjectTasksView(
              project: _work,
              api: api,
              token: () => 'token',
              moveTargets: () => const [_work],
              showTitle: showTitle,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double handleOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byIcon(Icons.drag_indicator),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('the header names the project and counts open tasks', (
    tester,
  ) async {
    api.seed('p1', 'A');
    api.seed('p1', 'B');
    api.seed('p1', 'Done', completed: true);
    await pumpView(tester);

    expect(find.text('کار'), findsOneWidget);
    expect(find.text('۲ کار باز'), findsOneWidget);
    expect(find.bySemanticsLabel('کار'), findsOneWidget);
  });

  testWidgets('an empty project says so and points at quick add', (
    tester,
  ) async {
    await pumpView(tester, showTitle: false);
    expect(find.text('کار'), findsNothing);
    expect(find.text('کار بازی نمانده'), findsOneWidget);
    expect(find.text('کار تازه را در نوار پایین بنویسید.'), findsOneWidget);
  });

  testWidgets('touch screens always show the drag handle after the title', (
    tester,
  ) async {
    api.seed('p1', 'A');
    await pumpView(tester);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.drag_indicator),
        matching: find.byType(AnimatedOpacity),
      ),
      findsNothing,
    );
    final tile = tester.widget<TaskTile>(find.byType(TaskTile));
    expect(tile.trailing, isNotNull);
    expect(tile.leading, isNull);
  });

  testWidgets(
    'pointer screens reveal the handle beside the checkbox on hover',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        api.seed('p1', 'A');
        await pumpView(tester);
        final tile = tester.widget<TaskTile>(find.byType(TaskTile));
        expect(tile.leading, isNotNull);
        expect(tile.trailing, isNull);
        expect(handleOpacity(tester), 0);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(find.text('A')));
        await tester.pumpAndSettle();
        expect(handleOpacity(tester), 1);

        await mouse.moveTo(const Offset(1, 690));
        await tester.pumpAndSettle();
        expect(handleOpacity(tester), 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
