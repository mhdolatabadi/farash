import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';

import 'support/fake_projects_api.dart';

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
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the Inbox', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));

    expect(find.widgetWithText(AppBar, 'صندوق ورودی'), findsOneWidget);
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
    expect(api.all.last.color, 'blue');
    // The new project is selected and the drawer closed.
    expect(find.widgetWithText(AppBar, 'کار'), findsOneWidget);
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

  testWidgets('wide screens keep the sidebar open', (tester) async {
    await pumpHome(tester, size: const Size(1200, 800));
    await projects.create(name: 'Work', color: 'blue');
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
    final work = await projects.create(name: 'Work', color: 'blue');
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
    expect(find.widgetWithText(AppBar, 'صندوق ورودی'), findsOneWidget);
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
      color: 'red',
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
