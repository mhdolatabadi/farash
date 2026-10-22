import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/search/search.dart';
import 'package:farash/features/search/search_view.dart';

import 'support/fake_tasks_api.dart';

class SearchFixture extends FakeTasksApi implements SearchApi {
  final requests = <Uri>[];
  bool fail = false;
  bool hasMore = false;
  final filters = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse(path);
    requests.add(uri);
    if (fail) throw const ApiException('invalid', statusCode: 400);
    if (uri.path == '/api/v1/search') {
      return {
        'tasks': [
          {
            'id': 'read',
            'project_id': 'work',
            'title': 'مطالعهٔ کتاب طراحی سیستم',
            'description': 'یادداشت‌ها',
            'priority': 2,
            'sort_order': 0,
          },
        ],
        'has_more': hasMore,
      };
    }
    if (method == 'POST') filters.add({'id': 'saved', ...body!});
    if (method == 'DELETE') filters.clear();
    return {'filters': filters};
  }
}

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
    testWidgets('search query and accessible layout ${variant.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = SearchFixture();
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
            home: SearchWorkspace(
              api: api,
              tasks: api,
              token: () => 'token',
              projects: () => const [
                Project(id: 'work', name: 'کار', color: '#98503D'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, 'امروز & p1');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(api.requests.last.queryParameters['q'], 'امروز & p1');
      expect(
        api.requests.last.queryParameters['today'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_GLASS_UI'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.impeccable/review/search-${variant.$1}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      api.fail = true;
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('عبارت فیلتر معتبر نیست'),
        200,
      );
      expect(find.textContaining('عبارت فیلتر معتبر نیست'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('saved filter persists confirmed query and reloads selection', (
    tester,
  ) async {
    final api = SearchFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: SearchWorkspace(
          api: api,
          tasks: api,
          token: () => 'token',
          projects: () => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'p1');
    await tester.tap(find.text('ذخیرهٔ فیلتر'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'نام فیلتر'),
      'مهم‌ها',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ذخیره'));
    await tester.pumpAndSettle();
    expect(api.filters.single['query'], 'p1');
    await tester.tap(find.text('مهم‌ها'));
    await tester.pumpAndSettle();
    expect(api.requests.last.queryParameters['q'], 'p1');
    expect(tester.takeException(), isNull);
  });
}
