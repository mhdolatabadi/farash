import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/tasks/presentation/due_tasks_view.dart';
import 'package:menval/features/tasks/presentation/quick_add_dialog.dart';
import 'package:menval/features/tasks/presentation/project_tasks_view.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';

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

  Future<void> openCompact(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('compact-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
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

  testWidgets('the account button is named by its tooltip, not the initial', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    final semantics = tester.ensureSemantics();
    // Android reads the tooltip as the button's name only while the
    // avatar's initial stays out of the label.
    final node = tester.getSemantics(find.byTooltip('حساب و تنظیمات'));
    expect(node.tooltip, 'حساب و تنظیمات');
    expect(node.label, isEmpty);
    semantics.dispose();
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

  testWidgets('medium widths have a compact menu and inline input', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(700, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('inline-task-title')), findsOneWidget);
    await openCompact(tester, 'امروز');
    expect(find.byType(DueTasksView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back returns to the start destination first', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    await openCompact(tester, 'تمرکز');
    expect(find.byType(ProjectTasksView), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTasksView), findsOneWidget);
  });

  testWidgets('Focus remains reachable through the compact menu', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 740));
    await openCompact(tester, 'تمرکز');
    expect(find.text('شروع تمرکز'), findsWidgets);
    expect(tester.takeException(), isNull);
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

  testWidgets('a long press opens a project row menu on touch', (tester) async {
    await pumpHome(tester, size: const Size(400, 800));
    final work = await projects.create(name: 'Work', color: '#2563eb');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(ValueKey('tree-${work.id}')));
    await tester.pumpAndSettle();

    expect(find.text('بایگانی'), findsOneWidget);
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

  testWidgets('q opens one capture dialog and leaves typing alone', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    await tester.tap(find.byType(TextField).first);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'q task');
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'q task',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('q is available on normal pushed pages, but never over a modal', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Focus(autofocus: true, child: Text('secondary page')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pageContext = tester.element(find.text('secondary page'));
    showDialog<void>(
      context: pageContext,
      builder: (_) => const AlertDialog(title: Text('existing modal')),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom input captures a task without opening the sheet', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.enterText(
      find.byKey(const ValueKey('inline-task-title')),
      'کار تازه',
    );
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsNothing);
    expect(find.text('کار اضافه شد.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary screens keep the inline capture field', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 740));
    await openCompact(tester, 'تمرکز');
    expect(find.byKey(const ValueKey('inline-task-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('inline-task-title')),
      'کار زمان‌دار',
    );
    await tester.tap(find.byKey(const ValueKey('quick-add-more')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('quick-add-title')),
    );
    expect(field.controller!.text, 'کار زمان‌دار');
    await tester.tap(find.byTooltip('بستن').last);
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced capture is a bottom sheet, not a side drawer', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quick-add-more')));
    await tester.pumpAndSettle();
    expect(find.byType(QuickAddDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.text('تاریخ و ساعت (اختیاری)'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

}
