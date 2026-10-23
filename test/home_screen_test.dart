import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  late FakeProjectsApi api;
  late ProjectsController projects;

  Future<void> pumpHome(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeProjectsApi();
    projects = ProjectsController(api: api, token: () => 'token');
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            email: 'a@example.com',
            onLogout: () {},
            projects: projects,
            tasksApi: FakeTasksApi(),
            token: () => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow RTL drawer owns selection ink per row after scroll', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 700));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'صندوق ورودی');
    final tileContext = tester.element(tile);
    final material = tileContext.findAncestorWidgetOfExactType<Material>();
    expect(material?.type, MaterialType.transparency);
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    await tester.drag(find.byType(ListView).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens on the Inbox', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));

    expect(
      find.descendant(
        of: find.byType(ProjectTasksView),
        matching: find.text('صندوق ورودی'),
      ),
      findsOneWidget,
    );
    expect(find.text('هنوز کاری در «صندوق ورودی» نیست.'), findsOneWidget);
  });

  testWidgets('creates a project from the drawer and opens it', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروژهٔ تازه'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'کار');
    await tester.tap(find.byTooltip('آبی'));
    await tester.tap(find.text('افزودن پروژه'));
    await tester.pumpAndSettle();

    expect(api.all.last.name, 'کار');
    expect(api.all.last.color, '#2563eb');
    // The new project is selected and the drawer closed.
    expect(
      find.descendant(
        of: find.byType(ProjectTasksView),
        matching: find.text('کار'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('an empty name is refused before calling the API', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروژهٔ تازه'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('افزودن پروژه'));
    await tester.pumpAndSettle();

    expect(find.text('نام پروژه را بنویسید.'), findsOneWidget);
    expect(api.all, hasLength(1));
  });

  testWidgets('medium widths move the destinations to a rail', (tester) async {
    await pumpHome(tester, size: const Size(700, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('امروز'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DueTasksView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back returns to the start destination first', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.widgetWithText(NavigationDestination, 'تمرکز'));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTasksView), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTasksView), findsOneWidget);
  });

  testWidgets('a running focus session shows its time on the destination', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    bool badged() => find
        .byWidgetPredicate((w) => w is Badge && w.isLabelVisible)
        .evaluate()
        .isNotEmpty;
    await tester.tap(find.widgetWithText(NavigationDestination, 'تمرکز'));
    await tester.pumpAndSettle();
    expect(badged(), isFalse);
    await tester.tap(find.text('شروع تمرکز'));
    await tester.pump();
    expect(badged(), isTrue);
    await tester.tap(find.text('مکث'));
    await tester.pump();
    expect(badged(), isFalse);
  });

  testWidgets('wide screens keep the sidebar open', (tester) async {
    await pumpHome(tester, size: const Size(1200, 800));
    await projects.create(name: 'Work', color: '#2563eb');
    await tester.pumpAndSettle();

    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Work'), findsOneWidget);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('هنوز کاری در «Work» نیست.'), findsOneWidget);
  });

  testWidgets('deleting asks first and falls back to the Inbox', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    final work = await projects.create(name: 'Work', color: '#2563eb');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('tree-${work.id}')),
        matching: find.byTooltip('گزینه‌های پروژه'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();

    expect(find.text('حذف «Work»؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(api.all.where((p) => p.name == 'Work'), isEmpty);
    expect(
      find.descendant(
        of: find.byType(ProjectTasksView),
        matching: find.text('صندوق ورودی'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the Inbox menu has no rename, archive or delete', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));

    await tester.tap(find.byTooltip('گزینه‌های پروژه').first);
    await tester.pumpAndSettle();

    expect(find.text('ویرایش'), findsOneWidget);
    expect(find.text('بایگانی'), findsNothing);
    expect(find.text('حذف'), findsNothing);
  });

  testWidgets('long Persian names do not overflow a narrow drawer', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 640));
    await projects.create(
      name:
          'پروژه‌ای با نامی بسیار طولانی که در یک خط جا نمی‌شود و باید کوتاه شود',
      color: '#dc2626',
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
