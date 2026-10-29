import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:farash/app/app_theme.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/calendar_connections/calendar_connections.dart';
import 'package:farash/features/calendar_connections/calendar_connections_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class CalendarFixture implements CalendarConnectionsApi {
  bool configured = true, connected = true, fail = false;
  String? failureCode;
  final requests = <(String, String, Map<String, Object?>?)>[];
  Completer<Map<String, dynamic>>? pending;
  bool selected = true;
  int version = 3;

  @override
  Future<Map<String, dynamic>> calendarRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    requests.add((token, method, body));
    if (fail) throw ApiException('provider failure', code: failureCode);
    if (pending case final delayed?) {
      pending = null;
      return delayed.future;
    }
    if (path.endsWith('/complete')) {
      connected = true;
      return {
        'connection': {
          'id': 'connection',
          'provider': 'google',
          'status': 'connected',
          'version': version,
        },
      };
    }
    if (path.endsWith('/authorize')) {
      return {
        'start_url':
            'https://todo.example.com/calendar-authorize/start?ticket=one-use',
      };
    }
    if (method == 'DELETE') {
      connected = false;
      return {'disconnected': true, 'revoked': false};
    }
    if (path.endsWith('/selection')) {
      expect(body!['version'], version);
      selected = (body['calendar_ids'] as List).contains('private/@calendar');
      version++;
      return {'version': version};
    }
    if (path.endsWith('/calendars')) {
      return {
        'version': version,
        'calendars': [
          {
            'id': 'private/@calendar',
            'title': 'تقویم شخصی با عنوان بلند برای مطالعه و جلسه‌های کاری',
            'time_zone': 'Asia/Tehran',
            'selected': selected,
          },
        ],
      };
    }
    if (Uri.parse(path).path.endsWith('/events')) {
      return {
        'complete': true,
        'events': [
          {
            'id': 'e',
            'calendar_id': 'private/@calendar',
            'title': 'جلسهٔ مطالعه',
            'start': {'date': '2026-10-25'},
            'end': {'date': '2026-10-26'},
            'read_only': true,
          },
        ],
      };
    }
    return {
      'configured': configured,
      'connections': connected
          ? [
              {
                'id': 'connection',
                'status': 'connected',
                'provider': 'google',
                'version': version,
              },
            ]
          : [],
    };
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

  test('late connection response is discarded when account changes', () async {
    var token = 'a';
    final api = CalendarFixture();
    final pending = api.pending = Completer<Map<String, dynamic>>();
    final controller = CalendarConnectionsController(
      api: api,
      token: () => token,
    );
    addTearDown(controller.dispose);
    final loading = controller.load();
    token = 'b';
    pending.complete({
      'configured': true,
      'connections': [
        {'id': 'private-a', 'status': 'connected'},
      ],
    });
    await loading;
    expect(controller.connection, isNull);
    expect(controller.calendars, isEmpty);
    expect(controller.error, contains('حساب تغییر'));
    expect(api.requests, hasLength(1));
  });

  test(
    'selection saves version and calendar ids without turning events into tasks',
    () async {
      final api = CalendarFixture();
      final controller = CalendarConnectionsController(
        api: api,
        token: () => 'a',
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.events.single.allDay, isTrue);
      controller.select('private/@calendar', false);
      await controller.saveSelection();
      expect(api.requests.where((r) => r.$2 == 'PUT').single.$3, {
        'calendar_ids': <String>[],
        'version': 3,
      });
      expect(controller.events, isEmpty);
      expect(controller.selectionChanged, isFalse);
      await controller.disconnect();
      expect(controller.connection, isNull);
      expect(controller.notice, contains('از حساب Google'));
    },
  );

  test(
    'provider reconnect error clears private events and offers reconnect',
    () async {
      final api = CalendarFixture();
      final controller = CalendarConnectionsController(
        api: api,
        token: () => 'a',
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.events, isNotEmpty);
      api.fail = true;
      api.failureCode = 'calendar_reconnect_required';
      await controller.moveWeek(1);
      expect(controller.connection!.needsReconnect, isTrue);
      expect(controller.events, isEmpty);
      expect(controller.calendars, isEmpty);
      api.fail = false;
      await controller.prepareAuthorization('android');
      expect(api.requests.last.$3, {'client': 'android', 'consent': true});
    },
  );

  test(
    'authorization ticket is one-use and cannot launch in another session',
    () async {
      var token = 'a';
      final api = CalendarFixture()..connected = false;
      final controller = CalendarConnectionsController(
        api: api,
        token: () => token,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await controller.prepareAuthorization('android');
      expect(api.requests.last.$3, {'client': 'android', 'consent': true});
      expect(controller.takeAuthorization()!.scheme, 'https');
      expect(controller.takeAuthorization(), isNull);
      await controller.prepareAuthorization('android');
      token = 'b';
      expect(controller.takeAuthorization(), isNull);
      expect(controller.authorization, isNull);
    },
  );

  for (final variant in [
    ('phone', const Size(390, 844), false, 1.0),
    ('dark-large', const Size(320, 760), true, 2.0),
    ('desktop', const Size(1280, 900), false, 1.0),
  ]) {
    final dark = variant.$3;
    testWidgets('calendar connections layout and recovery ${variant.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = variant.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = CalendarFixture();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? FarashTheme.dark() : FarashTheme.light(),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.$4)),
              child: child!,
            ),
          ),
          home: RepaintBoundary(
            key: boundaryKey,
            child: CalendarConnectionsView(
              api: api,
              token: () => 'a',
              openBrowser: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('حساب Google متصل است.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_GLASS_UI'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('.impeccable/review/calendar-${variant.$1}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(find.text('جلسهٔ مطالعه'), 250);
      expect(find.textContaining('· تمام‌روز'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('قطع اتصال Google'), 250);
      await tester.tap(find.text('قطع اتصال Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('انصراف'));
      await tester.pumpAndSettle();
      api.fail = true;
      await tester.tap(find.byTooltip('بررسی وضعیت اتصال'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('بازخوانی اطلاعات'), -250);
      expect(tester.takeException(), isNull);
      api.fail = false;
      await tester.tap(find.text('بازخوانی اطلاعات'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unconfigured provider does not expose working connect action', (
    tester,
  ) async {
    final api = CalendarFixture()
      ..configured = false
      ..connected = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarConnectionsView(api: api, token: () => 'a'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('هنوز روی این سرور فعال نشده'), findsOneWidget);
    expect(find.text('آماده‌سازی اتصال Google'), findsNothing);
  });

  testWidgets(
    'browser return stays pending until explicit authenticated completion',
    (tester) async {
      final api = CalendarFixture()..connected = false;
      Uri? launched;
      await tester.pumpWidget(
        MaterialApp(
          home: CalendarConnectionsView(
            api: api,
            token: () => 'a',
            openBrowser: (uri) async => launched = uri,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('آماده‌سازی اتصال Google'));
      await tester.pumpAndSettle();
      expect(launched, isNull);
      await tester.tap(find.text('باز کردن Google'));
      await tester.pumpAndSettle();
      expect(launched!.host, 'todo.example.com');
      expect(find.text('باز کردن Google'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('حساب Google متصل است.'), findsNothing);
      await tester.scrollUntilVisible(
        find.byType(TextField),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byType(TextField), 'a' * 43);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('ثبت اتصال'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('ثبت اتصال'));
      await tester.pumpAndSettle();
      expect(api.requests.where((r) => r.$2 == 'POST').last.$3, {
        'completion_code': 'a' * 43,
      });
      expect(find.byType(TextField), findsNothing);
      expect(find.text('حساب Google متصل است.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'late completion never exposes previous session credentials or events',
    () async {
      var token = 'a';
      final api = CalendarFixture()..connected = false;
      final controller = CalendarConnectionsController(
        api: api,
        token: () => token,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final reply = api.pending = Completer<Map<String, dynamic>>();
      final before = api.requests.length;
      final completion = controller.completeAuthorization('a' * 43);
      token = 'b';
      reply.complete({
        'connection': {'id': 'private-a', 'status': 'connected'},
      });
      await completion;
      expect(controller.connection, isNull);
      expect(controller.events, isEmpty);
      expect(api.requests, hasLength(before + 1));
      expect(controller.error, contains('حساب تغییر'));
    },
  );
}
