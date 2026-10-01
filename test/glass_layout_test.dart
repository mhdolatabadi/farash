import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  ]) {
    testWidgets('glass layout and editor: ${layout.$1}', (tester) async {
      tester.view.physicalSize = layout.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeTasksApi();
      api.seed('inbox', 'ادامهٔ مطالعهٔ کتاب', priority: TaskPriority.p1);
      api.seed('inbox', 'مرور یادداشت‌ها');
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
            theme: layout.$3 ? FarashTheme.dark() : FarashTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(layout.$4),
                disableAnimations: true,
              ),
              child: GlassBackdrop(child: child!),
            ),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: HomeScreen(
                email: 'demo@example.com',
                projects: projects,
                tasksApi: api,
                token: () => 'token',
                onLogout: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, captureKey, layout.$1);
      await tester.tap(find.text('ادامهٔ مطالعهٔ کتاب'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailEditor), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.pumpAndSettle();
      await _capture(tester, captureKey, '${layout.$1}-editor');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'عنوان'),
        'عنوان جدید',
      );
      await tester.ensureVisible(find.text('ذخیره'));
      await tester.tap(find.text('ذخیره'));
      await tester.pumpAndSettle();
      expect(api.byTitle('عنوان جدید').title, 'عنوان جدید');
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
