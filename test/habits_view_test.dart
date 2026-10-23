import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_detail.dart';
import 'package:farash/features/habits/habit_editor.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/habits/habits_view.dart';

import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';

import 'support/fake_habits_api.dart';
import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

class _ShellApi extends FakeTasksApi implements HabitsApi {
  final habits = seeded();

  @override
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) => habits.habitRequest(token, method, path, body: body);
}

final now = DateTime(2026, 10, 22, 12);
final today = epochDay(now);
String key(int offset) => dayKey(today - offset);

/// The calm light design the app is moving to, for review captures only.
final calm = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0E7490),
    primary: const Color(0xFF0E7490),
    surface: Colors.white,
    outlineVariant: const Color(0xFFEEF0F2),
  ),
  fontFamily: 'Vazirmatn',
);

FakeHabitsApi seeded() {
  final api = FakeHabitsApi();
  api.seed(
    'ورزش صبحگاهی',
    color: 0,
    entries: {
      for (final o in [0, 1, 3, 4, 5, 6, 8, 9, 10, 12, 13, 15, 20]) key(o): 1,
      key(2): 0,
    },
  );
  api.seed(
    'مطالعهٔ ۳۰ دقیقه',
    color: 8,
    num: 3,
    den: 7,
    entries: {
      for (final o in [1, 3, 6, 9, 11, 13]) key(o): 1,
    },
  );
  api.seed(
    'آب خوردن',
    color: 11,
    kind: 'numeric',
    target: 8,
    unit: 'لیوان',
    entries: {key(0): 6, key(1): 8, key(2): 8, key(3): 5, key(4): 7},
  );
  api.seed('بدون شبکهٔ اجتماعی بعد از ساعت ده شب و پیش از خواب', color: 13);
  return api;
}

Future<HabitsController> pump(
  WidgetTester tester,
  FakeHabitsApi api, {
  Size size = const Size(390, 844),
  ThemeData? theme,
  double textScale = 1,
  GlobalKey? captureKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = HabitsController(api: api, token: () => 't', now: now);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme ?? FarashTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(body: HabitsView(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('lists habits with today first and toggles a day', (
    tester,
  ) async {
    final api = seeded();
    final controller = await pump(tester, api);
    expect(find.text('ورزش صبحگاهی'), findsOneWidget);
    expect(find.text('آب خوردن'), findsOneWidget);
    // Today's cell sits next to the name; the numeric habit shows amounts.
    expect(find.text('۶'), findsOneWidget);

    final today = find.bySemanticsLabel(
      'مطالعهٔ ۳۰ دقیقه، امروز: در بازهٔ انجام‌شده',
    );
    expect(today, findsOneWidget);
    await tester.tap(today);
    await tester.pumpAndSettle();
    expect(api.calls.last.$1, 'PUT');
    expect(api.calls.last.$2, endsWith('/entries/${key(0)}'));
    expect(api.calls.last.$3, {'value': 1.0, 'skip': false});
    final habit = controller.all[1];
    expect(habit.entries[epochDay(now)]?.value, 1);

    // done → not done → skipped → unknown.
    for (final expected in ['انجام نشد', 'رد شد', 'در بازهٔ انجام‌شده']) {
      await tester.tap(
        find.bySemanticsLabel(RegExp('^مطالعهٔ ۳۰ دقیقه، امروز')),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('مطالعهٔ ۳۰ دقیقه، امروز: $expected'),
        findsOneWidget,
      );
    }
    expect(api.calls.last.$1, 'DELETE');
  });

  testWidgets('the shell offers habits as a destination', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final projects = ProjectsController(
      api: FakeProjectsApi(
        projects: const [
          Project(
            id: 'inbox',
            name: 'صندوق ورودی',
            isInbox: true,
            color: '#0F8B7C',
          ),
        ],
      ),
      token: () => 't',
    );
    addTearDown(projects.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: FarashTheme.light(),
        home: HomeScreen(
          email: 'demo@example.com',
          projects: projects,
          tasksApi: _ShellApi(),
          token: () => 't',
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عادت‌ها'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsView), findsOneWidget);
    expect(find.text('ورزش صبحگاهی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused check-in rolls back with a message', (tester) async {
    final api = seeded();
    await pump(tester, api);
    api.failNext = const ApiException('اتصال به سرور برقرار نشد.');
    await tester.tap(find.bySemanticsLabel('ورزش صبحگاهی، امروز: انجام شد'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('ورزش صبحگاهی، امروز: انجام شد'),
      findsOneWidget,
    );
    expect(find.textContaining('ثبت نشد'), findsOneWidget);
  });

  testWidgets('measurable habits take an amount', (tester) async {
    final api = seeded();
    await pump(tester, api);
    await tester.tap(find.bySemanticsLabel('آب خوردن، امروز: ۶ لیوان'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '۷٫۵');
    await tester.tap(find.text('ثبت'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3, {'value': 7.5, 'skip': false});
    expect(find.text('۷٫۵'), findsOneWidget);
  });

  testWidgets('creates a yes/no habit through Loop\'s flow', (tester) async {
    final api = FakeHabitsApi();
    await pump(tester, api);
    expect(find.text('هنوز عادتی نساخته‌اید.'), findsOneWidget);
    await tester.tap(find.text('عادت تازه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بله یا نه'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitEditor), findsOneWidget);
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(find.text('نام عادت را بنویسید.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'مدیتیشن');
    await tester.tap(find.text('هر روز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('۲ بار در هفته').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3, containsPair('freq_num', 2));
    expect(api.calls.last.$3, containsPair('freq_den', 7));
    expect(api.calls.last.$3, containsPair('kind', 'boolean'));
    expect(find.byType(HabitEditor), findsNothing);
    expect(find.text('مدیتیشن'), findsOneWidget);
  });

  testWidgets('detail shows every Loop section and archives', (tester) async {
    final api = seeded();
    await pump(tester, api);
    await tester.tap(find.text('ورزش صبحگاهی'));
    await tester.pumpAndSettle();
    expect(find.byType(HabitDetailScreen), findsOneWidget);
    for (final title in [
      'نمای کلی',
      'قدرت عادت',
      'تاریخچه',
      'تقویم',
      'بهترین زنجیره‌ها',
      'تکرار',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بایگانی'));
    await tester.pumpAndSettle();
    expect(api.calls.last.$3, {'archived': true});
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('ورزش صبحگاهی'), findsNothing);
  });

  for (final layout in [
    ('habits-phone', const Size(390, 844), false, 1.0),
    ('habits-narrow-dark-large', const Size(320, 700), true, 1.6),
    ('habits-desktop', const Size(1280, 800), false, 1.0),
  ]) {
    testWidgets('layout: ${layout.$1}', (tester) async {
      final captureKey = GlobalKey();
      final api = seeded();
      await pump(
        tester,
        api,
        size: layout.$2,
        theme: layout.$3 ? FarashTheme.dark() : FarashTheme.light(),
        textScale: layout.$4,
        captureKey: captureKey,
      );
      expect(tester.takeException(), isNull);
      // Every day cell is a full touch target.
      final cell = tester.getSize(find.byType(CheckCell).first);
      expect(cell.width, greaterThanOrEqualTo(48));
      expect(cell.height, greaterThanOrEqualTo(48));
      // The add button never covers the last habit.
      final last = find.textContaining('بدون شبکهٔ اجتماعی');
      await tester.scrollUntilVisible(
        last,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      final fab = tester.getRect(find.byType(FloatingActionButton));
      final row = tester.getRect(
        find.ancestor(of: last, matching: find.byType(HabitRow)),
      );
      expect(row.bottom <= fab.top || !row.overlaps(fab), isTrue);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, layout.$1);
      await tester.tap(find.text('ورزش صبحگاهی'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, '${layout.$1}-detail');
      await tester.scrollUntilVisible(
        find.text('تقویم'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, '${layout.$1}-detail-2');
    });
  }

  testWidgets('review capture in the calm design', (tester) async {
    final captureKey = GlobalKey();
    await pump(tester, seeded(), theme: calm, captureKey: captureKey);
    await _capture(tester, captureKey, 'habits-calm');
    await tester.tap(find.text('آب خوردن'));
    await tester.pumpAndSettle();
    await _capture(tester, captureKey, 'habits-calm-detail');
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
