import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/calendar_settings_dialog.dart';
import 'package:farash/core/settings/theme_preferences.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      ('Vazirmatn', 'assets/fonts/Vazirmatn-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  test('appearance persists and rejects unknown values', () async {
    final store = MemoryCalendarSettingsStore();
    final preferences = ThemePreferences(store: store);
    addTearDown(preferences.dispose);
    expect(preferences.mode, ThemeMode.system);
    await preferences.setMode(ThemeMode.dark);
    expect(store.values['theme_mode'], 'dark');
    final restored = ThemePreferences(store: store);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.mode, ThemeMode.dark);
    store.values['theme_mode'] = 'invalid';
    final fallback = ThemePreferences(store: store);
    addTearDown(fallback.dispose);
    await fallback.load();
    expect(fallback.mode, ThemeMode.system);
  });

  test('late storage read cannot overwrite an explicit choice', () async {
    final store = _DelayedStore();
    final preferences = ThemePreferences(store: store);
    addTearDown(preferences.dispose);
    final loading = preferences.load();
    await preferences.setMode(ThemeMode.light);
    store.readResult.complete('dark');
    await loading;
    expect(preferences.mode, ThemeMode.light);
    expect(store.written, 'light');
  });

  test('storage failures retain choice and can be retried', () async {
    final store = _FailingStore();
    final preferences = ThemePreferences(store: store);
    addTearDown(preferences.dispose);
    await preferences.load();
    await preferences.setMode(ThemeMode.dark);
    expect(preferences.mode, ThemeMode.dark);
    store.fail = false;
    await preferences.setMode(ThemeMode.dark);
    expect(store.written, 'dark');
  });

  testWidgets('appearance is selectable with narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = ThemePreferences();
    addTearDown(preferences.dispose);
    final calendar = CalendarSettings();
    addTearDown(calendar.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: ListenableBuilder(
          listenable: preferences,
          builder: (context, _) => MaterialApp(
            themeMode: preferences.mode,
            theme: FarashTheme.light(),
            darkTheme: FarashTheme.dark(),
            builder: (context, child) => ThemePreferencesScope(
              preferences: preferences,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showCalendarSettings(context, calendar),
                  child: const Text('settings'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, captureKey, 'appearance-narrow-large-light');
    await tester.tap(find.text('همگام با دستگاه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تیره').last);
    await tester.pumpAndSettle();
    expect(preferences.mode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(AlertDialog))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await capture(tester, captureKey, 'appearance-narrow-large-dark');
    await tester.ensureVisible(find.text('بستن'));
    await tester.tap(find.text('بستن'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
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

class _DelayedStore implements CalendarSettingsStore {
  final readResult = Completer<String?>();
  String? written;

  @override
  Future<String?> read(String key) => readResult.future;

  @override
  Future<void> write(String key, String value) async => written = value;
}

class _FailingStore implements CalendarSettingsStore {
  bool fail = true;
  String? written;

  @override
  Future<String?> read(String key) async => throw StateError('unavailable');

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('unavailable');
    written = value;
  }
}
