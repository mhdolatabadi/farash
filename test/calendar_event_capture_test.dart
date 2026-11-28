import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/calendar/time_zone.dart';
import 'package:menval/features/calendar/calendar_event_composer.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';
import 'package:menval/features/calendar/task_calendar_view.dart';
import 'package:menval/features/calendar/week_time_grid.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'support/fake_calendar_events_api.dart';

Future<void> pumpCalendar(WidgetTester tester, FakeCalendarEventsApi api,
    {Size size = const Size(1280, 900), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugTimeZoneOverride = 'UTC';
  addTearDown(() => debugTimeZoneOverride = null);
  final controller = CalendarEventsController(api: api, token: () => 'alice');
  final settings = CalendarSettings();
  addTearDown(controller.dispose);
  addTearDown(settings.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: MenvalTheme.light(),
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: CalendarScope(settings: settings, child: TaskCalendarView(
      events: controller,
      now: () => DateTime(2026, 11, 23, 9),
      loadTasks: (from, to) async => [Task(id: 'task', projectId: 'inbox',
        title: 'کار مستقل', due: TaskDue.onDay(DateTime(2026, 11, 23)))],
    )),
  ));
  await tester.pumpAndSettle();
}

void expectVisibleWeek(WidgetTester tester, {required double bottom}) {
  final grid = tester.getRect(find.byType(WeekTimeGrid));
  final days = [
    for (var day = 21; day <= 27; day++)
      tester.getRect(find.byKey(ValueKey('week-day-2026-11-$day'))),
  ];
  for (var index = 0; index < days.length; index++) {
    final day = days[index];
    expect(day.left, greaterThanOrEqualTo(grid.left));
    expect(day.right, lessThanOrEqualTo(grid.right + .01));
    expect(day.top, greaterThanOrEqualTo(grid.top));
    expect(day.bottom, lessThanOrEqualTo(bottom));
    if (index > 0) {
      expect(day.right, lessThanOrEqualTo(days[index - 1].left + .01));
    }
  }
  expect(grid.left, greaterThanOrEqualTo(0));
  expect(grid.right, lessThanOrEqualTo(320));
  expect(grid.bottom, lessThanOrEqualTo(bottom));
  final hour = tester.getRect(find.text('۰۸:۰۰'));
  expect(hour.left, greaterThanOrEqualTo(grid.left));
  expect(hour.right, lessThanOrEqualTo(days.last.left));
  expect(tester.getRect(find.text('تمام‌روز')).right,
      lessThanOrEqualTo(days.last.left));
}

void main() {
  testWidgets('inline creation keeps calendar visible and accepts Persian times', (tester) async {
    final api = FakeCalendarEventsApi();
    await pumpCalendar(tester, api);
    await tester.tap(find.byTooltip('رویداد جدید'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarEventComposer), findsOneWidget);
    expect(find.byType(WeekTimeGrid), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('کار مستقل'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'جلسه تازه');
    await tester.enterText(find.byKey(const ValueKey('event-start')), '۰۹:۳۰');
    await tester.enterText(find.byKey(const ValueKey('event-end')), '۱۰:۳۰');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(DateTime.parse(api.rows.single['start_at'] as String).toLocal().hour, 9);
    expect(DateTime.parse(api.rows.single['start_at'] as String).toLocal().minute, 30);
    expect(find.byType(CalendarEventComposer), findsNothing);
    expect(find.text('کار مستقل'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-event-event-1-2')), findsOneWidget);
  });

  testWidgets('failed create preserves draft and retries without duplication', (tester) async {
    final api = FakeCalendarEventsApi();
    await pumpCalendar(tester, api);
    await tester.tap(find.byTooltip('رویداد جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'عنوان محفوظ');
    await tester.enterText(find.byKey(const ValueKey('event-end')), '08:00');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(api.rows, isEmpty);
    expect(find.textContaining('پایان باید بعد'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('event-end')), '10:00');
    api.loseCreateResponse = true;
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(find.text('عنوان محفوظ'), findsOneWidget);
    expect(find.textContaining('اطلاعات فرم حفظ شده'), findsOneWidget);
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(api.rows, hasLength(1));
    expect(find.byType(CalendarEventComposer), findsNothing);
  });

  testWidgets('event opens inline for edit and deletion offers undo', (tester) async {
    final api = FakeCalendarEventsApi();
    await pumpCalendar(tester, api);
    await tester.tap(find.byTooltip('رویداد جدید'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'جلسه');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    final event = find.byKey(const ValueKey('week-event-event-1-2'));
    await tester.tap(event);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'جلسه اصلاح‌شده');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expect(api.rows.single['title'], 'جلسه اصلاح‌شده');
    await tester.tap(event);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('حذف رویداد'));
    await tester.pumpAndSettle();
    expect(event, findsNothing);
    await tester.tap(find.text('بازگردانی'));
    await tester.pumpAndSettle();
    expect(event, findsOneWidget);
  });

  testWidgets('narrow inline editor keeps seven days visible without overflow', (tester) async {
    final api = FakeCalendarEventsApi();
    await pumpCalendar(tester, api, size: const Size(320, 740));
    await tester.tap(find.byTooltip('رویداد جدید'));
    await tester.pumpAndSettle();
    expect(find.byType(WeekTimeGrid), findsOneWidget);
    expect(find.byKey(const ValueKey('event-title')), findsOneWidget);
    expectVisibleWeek(tester, bottom: 740);
    expect(tester.takeException(), isNull);
    api.failNext = const ApiException('offline');
    await tester.enterText(find.byKey(const ValueKey('event-title')), 'تست');
    await tester.tap(find.byTooltip('ذخیرهٔ رویداد'));
    await tester.pumpAndSettle();
    expectVisibleWeek(tester, bottom: 740);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and keyboard keep inline controls and week visible', (tester) async {
    final api = FakeCalendarEventsApi();
    await pumpCalendar(tester, api,
        size: const Size(320, 900), textScale: 2);
    await tester.tap(find.byTooltip('رویداد جدید'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    for (final tooltip in ['ذخیرهٔ رویداد', 'بستن فرم رویداد']) {
      final rect = tester.getRect(find.byTooltip(tooltip));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.bottom, lessThanOrEqualTo(680));
    }
    expectVisibleWeek(tester, bottom: 680);
    expect(tester.takeException(), isNull);
  });
}
