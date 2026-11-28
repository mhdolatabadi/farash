import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/app/controls.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:menval/core/settings/theme_preferences.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';
import 'package:menval/features/habits/habit.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';
import 'package:menval/features/search/search.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/task_detail_sheet.dart';
import 'package:menval/features/tasks/presentation/task_tile.dart';
import 'support/fake_habits_api.dart';
import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

class _WorkspaceApi extends FakeTasksApi implements HabitsApi, SearchApi, CalendarEventsApi {
  final habits = FakeHabitsApi();
  @override
  Future<Map<String, dynamic>> habitRequest(String token, String method, String path,
    {Map<String, Object?>? body}) => habits.habitRequest(token, method, path, body: body);
  @override
  Future<Map<String, dynamic>> searchRequest(String token, String method, String path,
    {Map<String, Object?>? body}) async => {'filters': <Object>[], 'tasks': <Object>[]};
  @override
  Future<Map<String, dynamic>> eventRequest(String token, String method, String path,
    {Map<String, Object?>? body}) async => {'events': <Object>[]};
}

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Vazirmatn', 'assets/fonts/Vazirmatn-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(path))).load();
    }
  });

  Future<(_WorkspaceApi, GlobalKey)> pump(WidgetTester tester, Size size, bool dark,
      {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _WorkspaceApi();
    final now = DateTime.now();
    DateTime at(int hour) => DateTime(now.year, now.month, now.day, hour);
    for (final (title, hour) in [('مرور طراحی منوال', 9), ('گزارش پروژه', 11), ('مطالعه DDIA', 20)]) {
      api.seed('inbox', title, dates: TaskDates(due: TaskDue.at(at(hour), 'Asia/Tehran'), durationMinutes: 60));
    }
    for (final name in ['مطالعه', 'ورزش', 'نوشتن', 'پیاده‌روی']) {
      api.habits.seed(name, entries: {dayKey(epochDay(now)): 1, dayKey(epochDay(now)-2): 1});
    }
    final projects = ProjectsController(api: FakeProjectsApi(), token: () => 'fixture');
    final preferences = ThemePreferences(mode: dark ? ThemeMode.dark : ThemeMode.light);
    addTearDown(projects.dispose);
    addTearDown(preferences.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'), supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
      builder: (context, child) => CalendarScope(settings: CalendarSettings(),
        child: ThemePreferencesScope(preferences: preferences,
          child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!))),
      home: HomeScreen(email: 'fixture@example.com', onLogout: () {}, projects: projects,
        tasksApi: api, token: () => 'fixture', startView: StartView(value: StartView.today)),
    )));
    await tester.pumpAndSettle();
    return (api, key);
  }

  testWidgets('desktop keeps tasks usable during inline capture and protects detail drafts', (tester) async {
    final (api, _) = await pump(tester, const Size(1440, 900), false);
    await tester.tap(find.text('مرور طراحی منوال'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailEditor), findsOneWidget);
    expect(find.byType(ModalBarrier), findsNothing);
    expect(tester.getRect(find.byType(TaskDetailEditor)).right,
      lessThan(tester.getRect(find.byType(TaskTile).first).left));
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'پیش‌نویس طراحی');
    await tester.tap(find.text('گزارش پروژه'));
    await tester.pumpAndSettle();
    expect(find.text('تغییرها ذخیره نشده‌اند'), findsOneWidget);
    await tester.tap(find.text('ادامهٔ ویرایش'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('task-title'))).controller!.text, 'پیش‌نویس طراحی');
    await tester.tap(find.byTooltip('کار جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('inline-task-title')), 'کار تازه');
    await tester.tap(find.byKey(const ValueKey('inline-task-submit')));
    await tester.pumpAndSettle();
    expect(api.all, hasLength(4));
    expect(find.text('کار تازه'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsNothing);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('task-title'))).controller!.text, 'پیش‌نویس طراحی');
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(1440, 900), const Size(1024, 768), const Size(320, 740)]) {
      testWidgets('approved workspace ${size.width} dark=$dark', (tester) async {
        final (_, key) = await pump(tester, size, dark);
        final mode = dark ? 'dark' : 'light';
        if (size.width >= 840) {
          expect(tester.getCenter(find.byKey(const ValueKey('menval-header-search'))).dx,
            lessThan(tester.getCenter(find.text('منوال').first).dx));
        }
        expect(tester.getSize(find.byType(TaskTile).first).height, lessThanOrEqualTo(60));
        await _capture(tester, key, 'workspace-tasks-${size.width.toInt()}-$mode');
        for (final (label, mobileKey, file) in [
          ('عادت‌ها', 'approved-nav-4', 'habits'), ('تقویم', 'approved-nav-5', 'calendar')]) {
          final target = size.width < 840 ? find.byKey(ValueKey(mobileKey)) : find.widgetWithText(ListTile, label);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
          await _capture(tester, key, 'workspace-$file-${size.width.toInt()}-$mode');
          expect(tester.takeException(), isNull);
        }
        expect(find.byType(MenvalCheckbox), findsNothing); // calendar has no task-completion targets
      });
    }
  }

  testWidgets('320px inline capture leaves scrolling content with keyboard and large text', (tester) async {
    await pump(tester, const Size(320, 740), true, scale: 2);
    await tester.tap(find.byKey(const ValueKey('menval-create-fab')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier), findsNothing);
    expect(find.byType(TaskTile), findsWidgets);
    expect(tester.getRect(find.byKey(const ValueKey('inline-task-submit'))).bottom, lessThan(520));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
