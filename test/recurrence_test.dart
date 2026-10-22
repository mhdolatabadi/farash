import 'dart:io';
import 'dart:ui' as ui;

import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/recurrence/recurrence_panel.dart';
import 'package:farash/features/recurrence/task_recurrence.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class RecurrenceFixture implements TimeApi {
  Map<String, dynamic>? saved;
  bool fail = false;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    calls.add('$method $path');
    expect(token, 'token');
    if (fail) throw StateError('offline');
    if (method == 'PUT') {
      saved = body?['schedule'] == null
          ? null
          : Map<String, dynamic>.from(body!['schedule'] as Map);
    }
    return {
      'recurrence': saved == null
          ? null
          : {
              'schedule': saved,
              'emitted': 1,
              'advanced_at': null,
              'next_task_id': null,
            },
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
  const task = Task(
    id: 'task/a',
    projectId: 'p',
    title: 'مطالعه',
    due: TaskDue(date: '2026-10-22'),
  );
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);
  test('transport encodes identity and leaves failure unconfirmed', () async {
    final api = RecurrenceFixture();
    final service = RecurrenceService(api, () => 'token');
    expect(await service.load(task.id), isNull);
    expect(api.calls.single, 'GET /api/v1/tasks/task%2Fa/recurrence');
    api.fail = true;
    await expectLater(
      service.save(task.id, {'start': '2026-10-22'}),
      throwsStateError,
    );
    expect(api.saved, isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('saves Persian recurrence interval at ${scale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = RecurrenceFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: FarashTheme.light(),
          locale: const Locale('fa'),
          supportedLocales: const [Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecurrencePanel(
                task: task,
                service: RecurrenceService(api, () => 'token'),
                datesSaved: true,
                onRefresh: () async {},
                onSkipped: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تکرار کار'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('تنظیم تکرار'));
      await tester.tap(find.text('تنظیم تکرار'));
      await tester.pumpAndSettle();
      final interval = find.widgetWithText(TextFormField, 'فاصلهٔ تکرار');
      await tester.ensureVisible(interval);
      await tester.enterText(interval, '۳');
      if (Platform.environment['CAPTURE_GLASS_UI'] == '1') {
        await tester.runAsync(() async {
          final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = File('.impeccable/review/recurrence-${scale}x.png');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('ذخیرهٔ تکرار'));
      await tester.pumpAndSettle();
      expect(api.saved?['start'], '2026-10-22');
      expect(api.saved?['timezone'], 'Asia/Tehran');
      expect((api.saved?['rule'] as Map)['interval'], 3);
      expect((api.saved?['rule'] as Map)['calendar'], 'jalali');
      expect(find.text('هر ۳ روز'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unsaved dates prevent activation', (tester) async {
    final api = RecurrenceFixture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecurrencePanel(
            task: task,
            service: RecurrenceService(api, () => 'token'),
            datesSaved: false,
            onRefresh: () async {},
            onSkipped: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('تکرار کار'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'تنظیم تکرار'))
          .onPressed,
      isNull,
    );
    expect(api.calls.where((c) => c.startsWith('PUT')), isEmpty);
  });
}
