import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

void main() {
  testWidgets('a phone list lines up on the gutter and the content keyline', (
    tester,
  ) async {
    const width = 375.0;
    tester.view.physicalSize = const Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeTasksApi()
      ..seed('p1', 'نان')
      ..seed('p1', 'کتاب');
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
              showTitle: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // RTL: a start edge is measured from the right.
    double start(Finder f) => width - tester.getTopRight(f).dx;

    // Each check circle sits on the gutter.
    final circle = tester.getRect(
      find
          .descendant(
            of: find.byType(TaskTile).first,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(width - circle.right, closeTo(Space.gutter, 2));

    // Task titles start on the content keyline.
    expect(start(find.text('نان')), closeTo(Space.keyline, 1));
    expect(start(find.text('کتاب')), closeTo(Space.keyline, 1));

    // The open count shares the title's start and sits close under it.
    expect(start(find.text('۲ کار باز')), start(find.text('کار')));
    final gap =
        tester.getTopRight(find.text('۲ کار باز')).dy -
        tester.getBottomRight(find.text('کار')).dy;
    expect(gap, lessThanOrEqualTo(Space.md));
  });
}
