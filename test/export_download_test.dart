import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'dart:typed_data';

import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/portability/export_api.dart';
import 'package:farash/features/portability/export_dialog.dart';
import 'package:farash/features/portability/export_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _body = jsonEncode({
  'format': 'farash-export',
  'version': 1,
  'exported_at': '2026-10-21T00:00:00Z',
  'preferences': <String, Object?>{},
  'records': {'tasks': <Object?>[]},
});

class _ExportApi implements ExportApi {
  int calls = 0;
  Future<Uint8List> Function()? load;

  @override
  Future<Uint8List> exportAccount(String token) async {
    calls++;
    return load == null ? Uint8List.fromList(utf8.encode(_body)) : load!();
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
  test('export preserves JSON and uses the authenticated base path', () async {
    final api = ApiClient(
      Uri.parse('https://example.com/farash'),
      client: MockClient((request) async {
        expect(request.url.path, '/farash/api/v1/export');
        expect(request.headers['Authorization'], 'Bearer private');
        return http.Response(_body, 200);
      }),
    );
    expect(utf8.decode(await api.exportAccount('private')), _body);
  });

  test('export rejects unknown document and throttling', () async {
    for (final response in [
      http.Response('{"format":"other"}', 200),
      http.Response('{}', 429),
    ]) {
      final api = ApiClient(
        Uri.parse('https://example.com'),
        client: MockClient((_) async => response),
      );
      await expectLater(
        api.exportAccount('private'),
        throwsA(isA<ExportException>()),
      );
    }
  });

  test(
    'oversize content length is rejected before stream subscription',
    () async {
      final client = MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          Stream<List<int>>.error(StateError('must not read')),
          200,
          contentLength: exportByteLimit + 1,
        ),
      );
      await expectLater(
        downloadAccountExport(client, Uri.parse('https://example.com'), 't'),
        throwsA(isA<ExportException>()),
      );
    },
  );

  for (final variant in [
    ('phone', const Size(390, 844), false, 1.0),
    ('dark', const Size(390, 844), true, 1.0),
    ('large-text', const Size(320, 760), true, 2.0),
    ('wide', const Size(1440, 900), false, 1.0),
  ]) {
    testWidgets(
      'export prepares once and retries cancelled save at ${variant.$1}',
      (tester) async {
        tester.view.physicalSize = variant.$2;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final api = _ExportApi();
        final key = GlobalKey();
        var saves = 0;
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
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(variant.$4)),
                child: child!,
              ),
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: AccountExportDialog(
                  api: api,
                  token: () => 't',
                  saver: (bytes) async {
                    saves++;
                    return saves == 1
                        ? ExportSaveResult.cancelled
                        : ExportSaveResult.saved;
                  },
                ),
              ),
            ),
          ),
        );
        await _capture(tester, key, 'export-initial-${variant.$1}');
        await tester.tap(find.text('آماده‌سازی خروجی'));
        await tester.pumpAndSettle();
        await _capture(tester, key, 'export-ready-${variant.$1}');
        await tester.ensureVisible(find.text('ذخیرهٔ فایل'));
        await tester.tap(find.text('ذخیرهٔ فایل'));
        await tester.pumpAndSettle();
        expect(
          find.text('ذخیره لغو شد. می‌توانید دوباره انتخاب کنید.'),
          findsOneWidget,
        );
        await tester.tap(find.text('ذخیرهٔ فایل'));
        await tester.pumpAndSettle();
        expect(find.text('فایل ذخیره شد.'), findsOneWidget);
        expect(api.calls, 1);
        expect(saves, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('account change prevents saving prior account bytes', (
    tester,
  ) async {
    var token = 'first';
    var saved = false;
    final api = _ExportApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AccountExportDialog(
          api: api,
          token: () => token,
          saver: (_) async {
            saved = true;
            return ExportSaveResult.saved;
          },
        ),
      ),
    );
    await tester.tap(find.text('آماده‌سازی خروجی'));
    await tester.pumpAndSettle();
    token = 'second';
    await tester.tap(find.text('ذخیرهٔ فایل'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(
      find.text('حساب تغییر کرده است. این پنجره را ببندید.'),
      findsOneWidget,
    );
  });

  testWidgets('dismissal during fetch never starts a save', (tester) async {
    final pending = Completer<Uint8List>();
    final api = _ExportApi()..load = () => pending.future;
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccountExport(
              context,
              api,
              () => 't',
              saver: (_) async {
                saved = true;
                return ExportSaveResult.saved;
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('آماده‌سازی خروجی'));
    await tester.pump();
    await tester.tap(find.text('بستن'));
    await tester.pumpAndSettle();
    pending.complete(Uint8List.fromList(utf8.encode(_body)));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
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
