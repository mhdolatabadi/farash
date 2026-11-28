import 'dart:async';

import 'package:flutter/material.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/calendar/time_zone.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/time_tracking/time_tracking.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/tasks/presentation/due_tasks_view.dart';
import 'package:menval/features/tasks/presentation/project_tasks_view.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';
import 'support/fake_habits_api.dart';

class _WorkspaceApi extends FakeTasksApi implements HabitsApi, CalendarEventsApi {
  final habits = FakeHabitsApi();
  final events = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> habitRequest(String token, String method,
      String path, {Map<String, Object?>? body}) =>
      habits.habitRequest(token, method, path, body: body);

  @override
  Future<Map<String, dynamic>> eventRequest(String token, String method,
      String path, {Map<String, Object?>? body}) async {
    if (method == 'GET') return {'events': events};
    final event = <String, dynamic>{...body!, 'id': 'event-${events.length + 1}', 'version': 1};
    events.add(event);
    return {'event': event};
  }
}

class _DelayedTasksApi extends FakeTasksApi {
  final release = Completer<void>();
  int creates = 0;
  @override
  Future<Task> createTask(String token, TaskDraft draft) async {
    creates++;
    await release.future;
    return super.createTask(token, draft);
  }
}

class _RecurringTasksApi extends FakeTasksApi implements TimeApi {
  bool failRule = true;
  final rulePaths = <String>[];
  @override
  Future<Map<String, dynamic>> timeRequest(String token, String method,
      String path, {Map<String, Object?>? body}) async {
    if (!path.endsWith('/recurrence')) return {
      'active': null, 'entries': <Object>[], 'tasks': <Object>[],
      'seconds': 0, 'today_seconds': 0, 'server_now': DateTime.now().toUtc().toIso8601String(),
    };
    rulePaths.add(path);
    if (failRule) throw const ApiException('پاسخ ذخیرهٔ تکرار نرسید.');
    return {'recurrence': {'schedule': body!['schedule'], 'emitted': 0}};
  }
}

void main() {
  late FakeProjectsApi api;
  late ProjectsController projects;
  late FakeTasksApi tasks;

  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);

  Future<void> pumpHome(WidgetTester tester, {required Size size, FakeTasksApi? tasksApi}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = FakeProjectsApi();
    tasks = tasksApi ?? FakeTasksApi();
    projects = ProjectsController(api: api, token: () => 'token');
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            startView: StartView(value: StartView.inbox),
            email: 'a@example.com',
            onLogout: () {},
            projects: projects,
            tasksApi: tasks,
            token: () => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCompact(WidgetTester tester, String label) async {
    if (label == 'امروز') {
      await tester.tap(find.byKey(const ValueKey('approved-nav-0')));
    } else if (label == 'عادت‌ها') {
      await tester.tap(find.byKey(const ValueKey('approved-nav-4')));
    } else if (label == 'تقویم') {
      await tester.tap(find.byKey(const ValueKey('approved-nav-5')));
    } else {
      await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, label).last);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('narrow RTL drawer owns selection ink per row after scroll', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 700));
    await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
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

    await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
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
    await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('پروژهٔ تازه'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('افزودن پروژه'));
    await tester.pumpAndSettle();

    expect(find.text('نام پروژه را بنویسید.'), findsOneWidget);
    expect(api.all, hasLength(1));
  });

  testWidgets('medium widths have the three-tab navigation and one FAB', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(700, 800));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('inline-task-title')), findsNothing);
    expect(find.byKey(const ValueKey('approved-nav-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('menval-create-fab')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('menval-wordmark'))).height,
      greaterThanOrEqualTo(48),
    );
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

  testWidgets('desktop overflow keeps optional tools gated by availability', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    await tester.tap(find.byKey(const ValueKey('compact-navigation')));
    await tester.pumpAndSettle();

    // No time-tracking API is configured for this test account.
    expect(find.text('زمان‌ها'), findsNothing);
    expect(find.text('بخش‌های بیشتر'), findsOneWidget);

    await tester.tap(find.text('بخش‌های بیشتر'));
    await tester.pumpAndSettle();
    // The overflow entry opens the project drawer; its account action is a
    // tooltip on a scrollable footer, not a visible Text widget.
    expect(find.text('صندوق ورودی'), findsWidgets);
    expect(tester.takeException(), isNull);
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
    await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
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
    await tester.tap(find.byKey(const ValueKey('menval-wordmark')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('q opens one inline capture and leaves its draft alone', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('inline-task-title'));
    expect(title, findsOneWidget);
    await tester.enterText(title, 'q task');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    expect(tester.widget<TextField>(title).controller!.text, 'q task');
    expect(find.byType(ModalBarrier), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('q only captures in the active workspace, never behind another route', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(1200, 800));
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: Focus(autofocus: true, child: Text('secondary page')),
      ),
    ));
    await tester.pumpAndSettle();
    final pageContext = tester.element(find.text('secondary page'));
    showDialog<void>(context: pageContext,
      builder: (_) => const AlertDialog(title: Text('existing modal')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-task-title'), skipOffstage: false), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-task-title'), skipOffstage: false), findsNothing);
    expect(find.text('secondary page'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-task-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task capture stays inline while existing tasks remain interactive', (
    tester,
  ) async {
    final taskApi = FakeTasksApi()..seed('inbox', 'کار موجود');
    await pumpHome(tester, size: const Size(400, 800), tasksApi: taskApi);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('inline-task-title'));
    expect(title, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ModalBarrier), findsNothing);
    expect(find.text('کار موجود'), findsOneWidget);
    await tester.enterText(title, 'کار تازه');
    await tester.tap(find.bySemanticsLabel('انجام «کار موجود»'));
    await tester.pumpAndSettle();
    expect(taskApi.byTitle('کار موجود').isCompleted, isTrue);
    expect(tester.widget<TextField>(title).controller!.text, 'کار تازه');
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(taskApi.all, hasLength(2));
    expect(find.text('کار تازه'), findsOneWidget);
    expect(tester.widget<TextField>(title).controller!.text, isEmpty);
    expect(title, findsOneWidget); // Ready for the next quick capture.
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary creation returns to tasks and preserves a closed draft', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(320, 740));
    await openCompact(tester, 'تمرکز');
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    expect(find.byType(DueTasksView), findsOneWidget);
    final title = find.byKey(const ValueKey('inline-task-title'));
    await tester.enterText(title, 'کار زمان‌دار');
    await tester.tap(find.byTooltip('بستن افزودن کار'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(title).controller!.text, 'کار زمان‌دار');
    expect(find.byType(ModalBarrier), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture exposes an optional date without a note field or overlay', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inline-task-title')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ModalBarrier), findsNothing);
    expect(find.text('تاریخ و ساعت'), findsOneWidget);
    expect(find.text('یادداشت'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed task create retains text and retries without a second task', (
    tester,
  ) async {
    await pumpHome(tester, size: const Size(400, 800));
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('inline-task-title'));
    await tester.enterText(title, 'خرید کتاب');
    tasks.failNext = const ApiException('اتصال برقرار نشد.');
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(tasks.all, isEmpty);
    expect(find.textContaining('اتصال برقرار نشد'), findsOneWidget);
    expect(tester.widget<TextField>(title).controller!.text, 'خرید کتاب');
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(tasks.all, hasLength(1));
    expect(tasks.all.single.title, 'خرید کتاب');
    expect(tester.widget<TextField>(title).controller!.text, isEmpty);
  });

  testWidgets('repeated submit while saving sends one task create', (tester) async {
    final taskApi = _DelayedTasksApi();
    await pumpHome(tester, size: const Size(400, 800), tasksApi: taskApi);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('inline-task-title')), 'فقط یک کار');
    final submit = find.byKey(const ValueKey('inline-task-submit'));
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(taskApi.creates, 1);
    taskApi.release.complete();
    await tester.pumpAndSettle();
    expect(taskApi.all, hasLength(1));
  });

  testWidgets('retrying a failed recurrence keeps the confirmed task ID', (tester) async {
    final taskApi = _RecurringTasksApi();
    await pumpHome(tester, size: const Size(400, 800), tasksApi: taskApi);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    await tester.pumpAndSettle();
    final title = find.byKey(const ValueKey('inline-task-title'));
    await tester.enterText(title, 'مطالعه هر روز');
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(taskApi.all, hasLength(1));
    expect(tester.widget<TextField>(title).controller!.text, 'مطالعه هر روز');
    expect(tester.widget<TextField>(title).enabled, isFalse);
    expect(find.textContaining('تکرارش ذخیره نشد'), findsOneWidget);
    taskApi.failRule = false;
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(taskApi.all, hasLength(1));
    expect(taskApi.rulePaths, [
      '/api/v1/tasks/${taskApi.all.single.id}/recurrence',
      '/api/v1/tasks/${taskApi.all.single.id}/recurrence',
    ]);
    expect(tester.widget<TextField>(title).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the icon-only plus creates a habit or independent event by destination', (
    tester,
  ) async {
    final workspace = _WorkspaceApi();
    await pumpHome(tester, size: const Size(400, 800), tasksApi: workspace);
    final fab = find.byKey(const ValueKey('menval-create-fab'));
    expect(tester.widget<FloatingActionButton>(fab).child, isA<Icon>());
    await openCompact(tester, 'عادت‌ها');
    expect(tester.widget<FloatingActionButton>(fab).tooltip, 'عادت جدید');
    await tester.tap(fab);
    await tester.pumpAndSettle();
    final habitTitle = find.byKey(const ValueKey('inline-habit-title'));
    expect(find.byKey(const ValueKey('inline-task-title')), findsNothing);
    expect(find.byType(ModalBarrier), findsNothing);
    await tester.enterText(habitTitle, 'نرمش روزانه');
    workspace.habits.failNext = const ApiException('اتصال برقرار نشد.');
    await tester.tap(find.byTooltip('ثبت عادت'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(habitTitle).controller!.text, 'نرمش روزانه');
    final firstKey = workspace.habits.calls.last.$3!['request_key'];
    await tester.tap(find.byTooltip('ثبت عادت'));
    await tester.pumpAndSettle();
    expect(workspace.habits.calls.last.$3!['request_key'], firstKey);
    expect(workspace.habits.habits, hasLength(1));
    expect(workspace.all, isEmpty);
    expect(find.text('نرمش روزانه'), findsOneWidget);

    await openCompact(tester, 'تقویم');
    expect(tester.widget<FloatingActionButton>(fab).tooltip, 'رویداد جدید');
    await tester.tap(fab);
    await tester.pumpAndSettle();
    final eventTitle = find.byKey(const ValueKey('event-title'));
    expect(eventTitle, findsOneWidget);
    expect(find.byType(ModalBarrier), findsNothing);
    await tester.enterText(eventTitle, 'جلسهٔ طراحی');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(workspace.events, hasLength(1));
    expect(workspace.events.single['title'], 'جلسهٔ طراحی');
    expect(workspace.all, isEmpty);
    expect(workspace.habits.habits, hasLength(1));
    expect(eventTitle, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
