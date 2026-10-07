import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Vazirmatn')
      ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    await font.load();
    final naskh = FontLoader('FarashNaskh')
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf'));
    await naskh.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final layout in [
    ('phone', const Size(375, 760), false, 1.0),
    ('phone-dark-large', const Size(320, 760), true, 2.0),
    ('desktop', const Size(1440, 900), false, 1.0),
    ('desktop-dark', const Size(1440, 900), true, 1.0),
    ('landscape', const Size(700, 375), false, 1.0),
    ('landscape-ime', const Size(700, 375), false, 1.0),
  ]) {
    testWidgets('glass layout and editor: ${layout.$1}', (tester) async {
      tester.view.physicalSize = layout.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeTasksApi();
      final today = DateTime.now();
      api.seed(
        'inbox',
        'ادامهٔ مطالعهٔ کتاب',
        priority: TaskPriority.p1,
        dates: TaskDates(due: TaskDue.onDay(today)),
      );
      api.seed(
        'inbox',
        'مرور یادداشت‌ها',
        priority: TaskPriority.p3,
        dates: TaskDates(
          due: TaskDue.onDay(today.add(const Duration(days: 1))),
        ),
      );
      api.seed('inbox', 'خرید نان');
      final projects = ProjectsController(
        api: FakeProjectsApi(
          projects: const [
            Project(
              id: 'inbox',
              name: 'صندوق ورودی',
              isInbox: true,
              color: '#0F8B7C',
            ),
            Project(id: 'work', name: 'کار', color: '#2563eb'),
            Project(id: 'home', name: 'خانه', color: '#16a34a'),
          ],
        ),
        token: () => 'token',
      );
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // As the app ships: Persian, so sheets and menus are RTL too.
            locale: const Locale('fa'),
            supportedLocales: const [Locale('fa')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: layout.$3 ? FarashTheme.dark() : FarashTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(layout.$4),
                disableAnimations: true,
              ),
              child: GlassBackdrop(child: child!),
            ),
            home: HomeScreen(
              email: 'demo@example.com',
              projects: projects,
              tasksApi: api,
              token: () => 'token',
              onLogout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (layout.$1 == 'landscape-ime') {
        await tester.enterText(find.byType(TextField), 'پیش‌نویس محفوظ');
        tester.view.viewInsets = const FakeViewPadding(bottom: 160);
        await tester.pumpAndSettle();
        expect(find.text('پیش‌نویس محفوظ'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      // One pane of glass per region, never glass on glass.
      expect(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(GlassSurface),
        ),
        findsNothing,
      );
      if (layout.$1 != 'landscape-ime') {
        // The bar names the project wherever the list is.
        expect(find.text('صندوق ورودی'), findsWidgets);
        // The last task scrolls clear of the capture bar.
        final last = find.text('خرید نان');
        await tester.scrollUntilVisible(
          last,
          80,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        final capture = tester.getRect(
          find.ancestor(
            of: find.byType(TextField),
            matching: find.byType(GlassSurface),
          ),
        );
        expect(tester.getRect(last).bottom, lessThanOrEqualTo(capture.top));
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
        await tester.pumpAndSettle();
      }
      await _capture(tester, captureKey, layout.$1);
      if (layout.$1 == 'landscape-ime') {
        await tester.scrollUntilVisible(
          find.text('ادامهٔ مطالعهٔ کتاب'),
          60,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await _capture(tester, captureKey, '${layout.$1}-tasks');
      }
      await tester.tap(find.text('ادامهٔ مطالعهٔ کتاب'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (layout.$1 == 'phone-dark-large') {
        for (final priority in TaskPriority.values) {
          final segment = find.byTooltip(priority.label);
          await tester.ensureVisible(segment);
          final size = tester.getRect(segment).size;
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.ensureVisible(find.byTooltip(TaskPriority.p2.label));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(TaskPriority.p2.label));
      }
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, '${layout.$1}-editor');
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        'عنوان جدید',
      );
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.byTitle('عنوان جدید').title, 'عنوان جدید');
      if (layout.$1 == 'phone-dark-large') {
        expect(api.byTitle('عنوان جدید').priority, TaskPriority.p2);
      }
      expect(find.byType(TaskDetailEditor), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      projects.dispose();
    });
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}
