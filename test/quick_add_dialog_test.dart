import 'dart:io';
import 'dart:ui' as ui;

import 'package:farash/app/app_theme.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/quick_capture.dart';
import 'package:farash/features/tasks/presentation/quick_add_dialog.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tasks_api.dart';

class _Api extends FakeTasksApi implements TimeApi {
  bool failRule = true;
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (failRule) throw StateError('transport unavailable');
    return {
      'recurrence': {'schedule': body!['schedule'], 'emitted': 0},
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
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);
  for (final dark in [false, true]) {
    testWidgets('quick capture keeps one task on retry, narrow $dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.reset);
      final api = _Api();
      const inbox = Project(
        id: 'inbox',
        name: '',
        color: '#98503D',
        isInbox: true,
      );
      final session = QuickCaptureSession(
        api: api,
        token: () => 'token',
        projects: () => [inbox],
        defaultProject: () => inbox,
      );
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            locale: const Locale('fa'),
            supportedLocales: const [Locale('fa')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? FarashTheme.dark() : FarashTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => QuickAddDialog(
                      session: session,
                      projectName: 'صندوق ورودی',
                    ),
                  ),
                  child: const Text('capture'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('capture'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'مطالعه هر روز');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'افزودن کار'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'افزودن کار'));
      await tester.pumpAndSettle();
      expect(api.all, hasLength(1));
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        find.textContaining('کار ساخته شد اما تکرارش ذخیره نشد.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      api.failRule = false;
      final retry = find.widgetWithText(FilledButton, 'ذخیرهٔ تکرار');
      await tester.ensureVisible(retry);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      if (Platform.environment['CAPTURE_GLASS_UI'] == '1') {
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '.impeccable/review/quick-capture-${dark ? 'dark' : 'light'}-large-text-ime.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(api.all, hasLength(1));
      expect(find.byType(QuickAddDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
