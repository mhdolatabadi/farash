import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:menval/features/habits/habit.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';
import 'package:menval/features/tasks/data/task.dart';

import 'support/fake_habits_api.dart';
import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

class _ApprovedPreviewApi extends FakeTasksApi implements HabitsApi {
  final _habits = FakeHabitsApi();

  @override
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) => _habits.habitRequest(token, method, path, body: body);

  void seedFixture() {
    final today = DateTime.now();
    DateTime at(int hour, int minute, {int delta = 0}) =>
        DateTime(today.year, today.month, today.day + delta, hour, minute);

    seed(
      'inbox',
      'مرور طراحی منوال',
      dates: TaskDates(
        due: TaskDue.at(at(9, 30), 'Asia/Tehran'),
        durationMinutes: 60,
      ),
    );
    seed(
      'inbox',
      'آماده‌سازی گزارش پروژه',
      dates: TaskDates(
        due: TaskDue.at(at(11, 0), 'Asia/Tehran'),
        durationMinutes: 90,
      ),
    );
    seed(
      'inbox',
      'مطالعه DDIA',
      dates: TaskDates(
        due: TaskDue.at(at(20, 0), 'Asia/Tehran'),
        durationMinutes: 45,
      ),
    );
    seed('inbox', 'پاسخ به پیام‌ها', dates: TaskDates(due: TaskDue.onDay(at(0, 0))));
    seed('inbox', 'مرور کارهای فردا', dates: TaskDates(due: TaskDue.onDay(at(0, 0))));

    // Other weekdays have simultaneous events, as in the approved time grid.
    seed(
      'inbox',
      'کلاس',
      dates: TaskDates(
        due: TaskDue.at(at(13, 0, delta: 1), 'Asia/Tehran'),
        durationMinutes: 60,
      ),
    );
    seed(
      'inbox',
      'ورزش',
      dates: TaskDates(
        due: TaskDue.at(at(15, 0, delta: 2), 'Asia/Tehran'),
        durationMinutes: 70,
      ),
    );
    seed(
      'inbox',
      'جلسه',
      dates: TaskDates(
        due: TaskDue.at(at(10, 0, delta: -1), 'Asia/Tehran'),
        durationMinutes: 60,
      ),
    );

    final todayDay = epochDay(today);
    Map<String, double> checked(List<int> offsets) => {
      for (final delta in offsets) dayKey(todayDay - delta): 1,
    };
    _habits.seed('مطالعه', entries: checked([0, 1, 3, 4]));
    _habits.seed('ورزش', entries: checked([1, 3]));
    _habits.seed('نوشتن', entries: checked([0, 2, 4]));
    _habits.seed('پیاده‌روی', entries: checked([0, 1, 2, 3]));
  }
}

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('approved three-screen shell renders with no extra input or titles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = _ApprovedPreviewApi()..seedFixture();
    final projects = ProjectsController(
      api: FakeProjectsApi(),
      token: () => 'fixture',
    );
    addTearDown(projects.dispose);
    final key = GlobalKey();

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa'),
          supportedLocales: const [Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: MenvalTheme.light(),
          builder: (context, child) =>
              CalendarScope(settings: CalendarSettings(), child: child!),
          home: HomeScreen(
            email: 'fixture@example.com',
            onLogout: () {},
            projects: projects,
            tasksApi: api,
            token: () => 'fixture',
            startView: StartView(value: StartView.today),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menval-wordmark')), findsOneWidget);
    expect(find.byKey(const ValueKey('menval-create-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-task-title')), findsNothing);
    expect(find.byKey(const ValueKey('approved-nav-0')), findsOneWidget);
    expect(find.text('مرور طراحی منوال'), findsOneWidget);
    await _capture(tester, key, 'approved-reference-tasks');

    await tester.tap(find.byKey(const ValueKey('approved-nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('مطالعه'), findsOneWidget);
    expect(find.byKey(const ValueKey('menval-create-fab')), findsOneWidget);
    await _capture(tester, key, 'approved-reference-habits');

    await tester.tap(find.byKey(const ValueKey('approved-nav-5')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menval-create-fab')), findsOneWidget);
    expect(find.byKey(const ValueKey('inline-task-title')), findsNothing);
    await _capture(tester, key, 'approved-reference-week');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
