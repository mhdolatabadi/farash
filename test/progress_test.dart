import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/glass.dart';

import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/progress/progress_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> progressJson({int completed = 1, int goal = 3}) => {
  'completed': completed,
  'xp': completed * 10,
  'level': completed ~/ 10 + 1,
  'level_xp': completed * 10 % 100,
  'weekly_days': completed == 0 ? 0 : 1,
  'weekly_goal': goal,
  'week_start': '2026-10-10',
  'badges': completed == 0 ? <String>[] : ['first_step'],
};

void main() {
  setUpAll(() async {
    for (final font in [
      ('Vazirmatn', 'assets/fonts/Vazirmatn-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);

  test(
    'progress requests use authentication and time zone; goal is saved',
    () async {
      final api = ApiClient(
        Uri.parse('https://farash.example'),
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer private-token');
          expect(request.url.path, '/api/v1/progress');
          expect(request.url.queryParameters['timezone'], 'Asia/Tehran');
          if (request.method == 'PATCH') {
            expect(jsonDecode(request.body), {'weekly_goal': 5});
          }
          return http.Response(jsonEncode(progressJson(goal: 5)), 200);
        }),
      );
      expect((await api.loadProgress('private-token', 'Asia/Tehran')).xp, 10);
      expect(
        (await api.saveProgressGoal(
          'private-token',
          'Asia/Tehran',
          5,
        )).weeklyGoal,
        5,
      );
    },
  );

  testWidgets('narrow RTL progress opens details and saves a weekly goal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captureKey = GlobalKey();
    var goal = 3;
    final api = ApiClient(
      Uri.parse('https://farash.example'),
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          goal =
              (jsonDecode(request.body) as Map<String, dynamic>)['weekly_goal']
                  as int;
        }
        return http.Response(jsonEncode(progressJson(goal: goal)), 200);
      }),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa'),
          supportedLocales: const [Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: FarashTheme.light(),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: GlassBackdrop(child: child!),
          ),
          home: Scaffold(
            body: ProgressCard(api: api, token: () => 'token'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('سطح ۱ · ۱۰ امتیاز'), findsOneWidget);
    await tester.tap(find.text('پیشرفت من'));
    await tester.pumpAndSettle();
    expect(find.text('قدم‌های کوچک، پیشرفت ماندگار'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('۵ روز در هفته').last);
    await tester.pumpAndSettle();
    await _capture(tester, captureKey);
    expect(goal, 5);
    expect(find.text('۵ روز در هفته'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('صد قدم جلوتر'), 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed load offers retry without displaying false zero progress',
    (tester) async {
      var failing = true;
      final api = ApiClient(
        Uri.parse('https://farash.example'),
        client: MockClient(
          (_) async => failing
              ? http.Response('{"error":"progress_unavailable"}', 500)
              : http.Response(jsonEncode(progressJson()), 200),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressCard(api: api, token: () => 'token'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('پیشرفت دریافت نشد؛ دوباره تلاش کنید.'), findsOneWidget);
      expect(find.textContaining('سطح'), findsNothing);
      failing = false;
      await tester.tap(find.text('پیشرفت من'));
      await tester.pumpAndSettle();
      expect(find.text('سطح ۱ · ۱۰ امتیاز'), findsOneWidget);
    },
  );

  testWidgets('server-confirmed mutations refresh the summary', (tester) async {
    var completed = 0;
    final api = ApiClient(
      Uri.parse('https://farash.example'),
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode(progressJson(completed: completed)), 200),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProgressCard(api: api, token: () => 'token'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('سطح ۱ · ۰ امتیاز'), findsOneWidget);
    completed = 1;
    api.progressChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('سطح ۱ · ۱۰ امتیاز'), findsOneWidget);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key) async {
  if (Platform.environment['CAPTURE_GLASS_UI'] != '1') return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.impeccable/review/progress-phone.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
