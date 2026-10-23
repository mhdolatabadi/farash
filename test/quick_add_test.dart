import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

import 'support/fake_labels_api.dart';
import 'support/fake_tasks_api.dart';

const _inbox = Project(id: 'inbox', name: 'x', isInbox: true, color: '#0F8B7C');
const _work = Project(id: 'work', name: 'کار', color: '#2563eb');

void main() {
  late FakeTasksApi api;
  late FakeLabelsApi labelsApi;
  late LabelsController labels;
  final tomorrow = dayOf(DateTime.now()).add(const Duration(days: 1));

  setUp(() {
    api = FakeTasksApi();
    labelsApi = FakeLabelsApi(tasks: api);
    labels = LabelsController(api: labelsApi, token: () => 'token');
    debugTimeZoneOverride = 'Asia/Tehran';
  });
  tearDown(() => debugTimeZoneOverride = null);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await labels.load();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            CalendarScope(settings: CalendarSettings(), child: child!),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ProjectTasksView(
              project: _inbox,
              api: api,
              token: () => 'token',
              moveTargets: () => const [_inbox, _work],
              labels: labels,
              showTitle: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('recurring capture freezes its draft until request settles', (
    tester,
  ) async {
    final ready = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickAddBar(onAdd: (_, _, _) => ready.future)),
      ),
    );
    await tester.enterText(find.byType(TextField), 'مطالعه هر روز');
    await tester.tap(find.byTooltip('افزودن کار'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted,
      isNull,
    );
    ready.complete(false);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'مطالعه هر روز',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick add sets date, time, priority and labels from text', (
    tester,
  ) async {
    final phone = labelsApi.seed('تلفن');
    await pump(tester);
    await tester.enterText(
      find.byType(TextField),
      'تماس با علی فردا ساعت ۵ عصر @تلفن @تازه p2',
    );
    await tester.pumpAndSettle();
    // Each recognised part shows as a chip while typing.
    expect(find.widgetWithText(InputChip, 'فردا'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'ساعت ۵ عصر'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    final task = api.byTitle('تماس با علی');
    expect(task.priority, TaskPriority.p2);
    expect(task.due!.isTimed, isTrue);
    expect(task.due!.localTime!.hour, 17);
    expect(dayOf(task.due!.localTime!), tomorrow);
    expect(task.labelIds.first, phone.id);
    expect(task.labelIds, hasLength(2));
    expect(
      (await labelsApi.listLabels('t')).map((l) => l.name),
      contains('تازه'),
    );
  });

  testWidgets('a dismissed part stays in the title; #project files it there', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'خواندن کتاب فردا #کار');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('نادیده گرفتن «فردا»'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'فردا'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    final task = api.byTitle('خواندن کتاب فردا');
    expect(task.due, isNull);
    expect(task.projectId, 'work');
    expect(find.text('«خواندن کتاب فردا» به «کار» اضافه شد.'), findsOneWidget);
  });
}
