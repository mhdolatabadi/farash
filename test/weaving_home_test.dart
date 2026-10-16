import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/weaving/weaving_home.dart';
import 'package:farash/features/weaving/woven_rug.dart';
import 'package:farash/features/focus/focus_view.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'support/fake_tasks_api.dart';
import 'support/fake_projects_api.dart';

void main() {
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);
  setUpAll(() async {
    for (final font in [
      ('Vazirmatn', 'assets/fonts/Vazirmatn-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  for (final variant in [
    ('weaving-phone', const Size(390, 844), false, 1.0),
    ('weaving-dark', const Size(390, 844), true, 1.0),
    ('weaving-large-text', const Size(320, 760), false, 2.0),
    ('weaving-desktop', const Size(1440, 900), false, 1.0),
  ]) {
    testWidgets('weaving layout and navigation ${variant.$1}', (tester) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tasks = FakeTasksApi()..seed('inbox', 'مطالعهٔ فصل اول کتاب');
      final projects = ProjectsController(
        api: FakeProjectsApi(),
        token: () => 'token',
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('fa'),
            supportedLocales: const [Locale('fa')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: variant.$3 ? FarashTheme.dark() : FarashTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(variant.$4),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: HomeScreen(
              email: 'weaving@example.com',
              onLogout: () {},
              projects: projects,
              tasksApi: tasks,
              token: () => 'token',
              startView: StartView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WeavingHome), findsOneWidget);
      expect(find.textContaining('امتیاز'), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/weaving/loom.png'),
          tester.element(find.byType(WeavingHome)),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, variant.$1);
      if (variant.$4 == 1) {
        await tester.tap(find.text('تمرکز').last);
        await tester.pumpAndSettle();
        expect(find.byType(FocusView), findsOneWidget);
        await capture(tester, key, '${variant.$1}-focus');
        if (variant.$1 == 'weaving-phone') {
          await tester.tap(find.text('شروع تمرکز'));
          await tester.pump();
          await tester.tap(find.text('کارها').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('تمرکز').last);
          await tester.pumpAndSettle();
          final timer = tester
              .widget<FocusView>(find.byType(FocusView))
              .controller;
          expect(timer.running, isTrue);
          expect(find.text('مکث'), findsOneWidget);
          await tester.tap(find.text('فرش').last);
          await tester.pumpAndSettle();
          tester
              .widget<WeavingHome>(find.byType(WeavingHome))
              .onFocus('کار دوم');
          await tester.pumpAndSettle();
          expect(find.textContaining('جلسهٔ قبلی هنوز'), findsOneWidget);
          expect(timer.running, isTrue);
          expect(timer.taskTitle, isNull);
          timer.pause();
        }
        await tester.tap(find.text('کارها').last);
        await tester.pumpAndSettle();
        expect(find.byType(ProjectTasksView), findsOneWidget);
        expect(find.text('مطالعهٔ فصل اول کتاب'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets('focus controls stay reachable at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final timer = FocusController();
    addTearDown(timer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FarashTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: FocusView(controller: timer),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('شروع تمرکز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شروع تمرکز'));
    await tester.pump();
    expect(timer.running, isTrue);
    expect(tester.takeException(), isNull);
    timer.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('server confirmed completion weaves rows and undo restores it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var count = 49;
    var closed = false;
    final task = {
      'id': 'task-1',
      'project_id': 'inbox',
      'title': 'مطالعهٔ کتاب',
    };
    final api = ApiClient(
      Uri.parse('https://farash.example'),
      client: MockClient((request) async {
        Object body;
        if (request.url.path.endsWith('/progress')) {
          body = {
            'completed': count,
            'xp': count * 10,
            'level': count ~/ 10 + 1,
            'level_xp': count * 10 % 100,
            'weekly_days': 1,
            'weekly_goal': 3,
            'badges': ['first_step'],
          };
        } else if (request.url.path.endsWith('/close')) {
          count++;
          closed = true;
          body = {
            'task': {...task, 'completed_at': DateTime.now().toIso8601String()},
          };
        } else if (request.url.path.endsWith('/reopen')) {
          count--;
          closed = false;
          body = {'task': task};
        } else {
          body = {
            'tasks': closed ? [] : [task],
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final projects = ProjectsController(
      api: FakeProjectsApi(),
      token: () => 'token',
    );
    await projects.load();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: FarashTheme.light(),
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: WeavingHome(
                api: api,
                token: () => 'token',
                projects: projects,
                onTasks: () {},
                onProject: (_) {},
                onFocus: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('۴۹ کار انجام‌شده · ۴۹۰ امتیاز'), findsOneWidget);
    final complete = find.byTooltip('انجام «مطالعهٔ کتاب»');
    await tester.ensureVisible(complete);
    await tester.pumpAndSettle();
    await tester.tap(complete);
    await tester.pumpAndSettle();
    expect(count, 50);
    expect(find.text('۵۰ کار انجام‌شده · ۵۰۰ امتیاز'), findsOneWidget);
    expect(tester.widget<RugPattern>(find.byType(RugPattern).first).rows, 0);
    await tester.tap(find.text('برگرداندن'));
    await tester.pumpAndSettle();
    expect(count, 49);
    expect(find.text('۴۹ کار انجام‌شده · ۴۹۰ امتیاز'), findsOneWidget);
    expect(tester.widget<RugPattern>(find.byType(RugPattern).first).rows, 49);
    count = 75;
    api.progressChanges.value++;
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/weaving/rug.png'),
        tester.element(find.byType(WeavingHome)),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, key, 'weaving-earned-progress');
    final collection = find.text('فرش‌های من · ۱');
    await tester.ensureVisible(collection);
    await tester.tap(collection);
    await tester.pumpAndSettle();
    expect(find.text('فرش ۱'), findsOneWidget);
    expect(tester.widget<RugPattern>(find.byType(RugPattern).last).rows, 50);
    await capture(tester, key, 'weaving-collection');
    expect(tester.takeException(), isNull);
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
