import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/scrum/scrum.dart';
import 'package:farash/features/scrum/scrum_view.dart';
import 'support/fake_scrum_api.dart';

const personal = Project(id: 'personal', name: 'پروژهٔ شخصی', color: '#98503D');
void main() {
  setUpAll(() async {
    for (final font in [
      ('Vazirmatn', 'assets/fonts/Vazirmatn-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  for (final variant in [
    ('phone', const Size(390, 844), false, 1.0),
    ('dark', const Size(390, 844), true, 1.0),
    ('large-text', const Size(320, 760), true, 2.0),
    ('wide', const Size(1440, 900), false, 1.0),
  ]) {
    testWidgets('personal Scrum lifecycle and layout ${variant.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeScrumApi();
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
            home: Scaffold(
              body: ProjectWorkspace(
                project: personal,
                api: api,
                tasks: api,
                token: () => 'token',
                projects: () => [personal],
                simple: const Text('simple list'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('اسپرینت تازه'), findsOneWidget);
      expect(find.textContaining('نیاز به تیم'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'scrum-${variant.$1}-backlog');
      await tester.ensureVisible(find.text('شروع اسپرینت'));
      await tester.tap(find.text('شروع اسپرینت'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شروع'));
      await tester.pumpAndSettle();
      expect(api.state, 'active');
      await tester.ensureVisible(find.text('برد اسپرینت'));
      await tester.tap(find.text('برد اسپرینت'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'scrum-${variant.$1}-board');
      await tester.ensureVisible(find.byTooltip('گزینه‌های اسکرام').first);
      await tester.tap(find.byTooltip('گزینه‌های اسکرام').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('انتقال به انجام‌شده'));
      await tester.pumpAndSettle();
      expect(
        api.all.where((t) => t.projectId == 'personal' && t.isCompleted).length,
        1,
      );
      await tester.ensureVisible(find.text('گزارش و مرور'));
      await tester.tap(find.text('گزارش و مرور'));
      await tester.pumpAndSettle();
      expect(find.textContaining('انجام‌شده: ۱ از ۲'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'scrum-${variant.$1}-report');
      await tester.ensureVisible(find.text('بک‌لاگ').first);
      await tester.tap(find.text('بک‌لاگ').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('پایان اسپرینت'));
      await tester.tap(find.text('پایان اسپرینت'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'مرور · چه خروجی‌ای داشتیم؟'),
        'یک کار تمام شد.',
      );
      await capture(tester, key, 'scrum-${variant.$1}-closure');
      await tester.ensureVisible(find.text('ثبت و پایان'));
      await tester.tap(find.text('ثبت و پایان'));
      await tester.pumpAndSettle();
      expect(api.state, 'closed');
      expect(api.review, 'یک کار تمام شد.');
      expect(
        api.metadata.values.where((v) => v['sprint_id'] == null),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
  test('failed writes never replace confirmed method or sprint', () async {
    final api = FakeScrumApi();
    final c = ScrumController(
      api: api,
      tasks: api,
      token: () => 'token',
      projectId: 'personal',
    );
    await c.load();
    api.fail = true;
    expect(await c.write('PATCH', '', {'method': 'simple'}), isFalse);
    expect(c.data!.method, 'scrum');
    expect(c.data!.sprints.first.state, 'planned');
    expect(c.error, isNotNull);
    c.dispose();
  });
  test('failed board PUT reloads an already-confirmed reopen', () async {
    final api = RejectingScrumApi();
    final c = ScrumController(
      api: api,
      tasks: api,
      token: () => 'token',
      projectId: 'personal',
    );
    await c.load();
    final id = c.data!.items.first.task.id;
    await api.closeTask('token', id);
    await c.load();
    api.rejectPut = true;
    expect(await c.move(c.data!.items.first, 'doing'), isFalse);
    expect(c.data!.items.first.task.isCompleted, isFalse);
    expect(c.error, isNotNull);
    c.dispose();
  });
  testWidgets('completed backlog work can be reopened in the Scrum workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeScrumApi();
    final task = api.byTitle('انتخاب فصل بعدی');
    await api.closeTask('token', task.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectWorkspace(
            project: personal,
            api: api,
            tasks: api,
            token: () => 'token',
            projects: () => [personal],
            simple: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('انجام‌شده‌های بک‌لاگ'));
    await tester.tap(find.text('انجام‌شده‌های بک‌لاگ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.bySemanticsLabel('برگرداندن «انتخاب فصل بعدی»'),
    );
    await tester.tap(find.bySemanticsLabel('برگرداندن «انتخاب فصل بعدی»'));
    await tester.pumpAndSettle();
    expect(api.byTitle('انتخاب فصل بعدی').isCompleted, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Persian story points and optional personal criteria save as metadata',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeScrumApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProjectWorkspace(
              project: personal,
              api: api,
              tasks: api,
              token: () => 'token',
              projects: () => [personal],
              simple: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('گزینه‌های اسکرام').first);
      await tester.tap(find.byTooltip('گزینه‌های اسکرام').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('برآورد و اسپرینت'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'امتیاز داستان · اختیاری'),
        '۵',
      );
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.calls.last.$3!['points'], 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class RejectingScrumApi extends FakeScrumApi {
  bool rejectPut = false;
  @override
  Future<Map<String, dynamic>> agileRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) {
    if (rejectPut && method == 'PUT') throw StateError('offline');
    return super.agileRequest(token, method, path, body: body);
  }
}
