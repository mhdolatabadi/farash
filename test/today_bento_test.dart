import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/projects/data/project.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/due_tasks_view.dart';
import 'package:menval/features/tasks/presentation/today_workspace.dart';

import 'support/fake_tasks_api.dart';

const _inbox = Project(
  id: 'inbox',
  name: 'Inbox',
  isInbox: true,
  color: '#0F8B7C',
);

void main() {
  final today = dayOf(DateTime.now());
  late FakeTasksApi api;
  late FocusController focus;

  setUp(() {
    api = FakeTasksApi();
    focus = FocusController();
    api.seed(
      'inbox',
      'مرور یادداشت‌ها',
      dates: TaskDates(due: TaskDue.onDay(today)),
    );
  });

  tearDown(() => focus.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Future<int?> Function()? doneToday,
    VoidCallback? onOpenFocus,
    Size size = const Size(400, 900),
    double textScale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: CalendarScope(settings: CalendarSettings(), child: child!),
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: DueTasksView(
              view: DueView.today,
              api: api,
              token: () => 'token',
              projects: () => const [_inbox],
              onOpenProject: (_) {},
              doneToday: doneToday,
              focus: focus,
              onOpenFocus: onOpenFocus,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Today shows one task list without categories or dashboard', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => 3, onOpenFocus: () {});
    final workspace = find.byType(TodayWorkspace);
    expect(workspace, findsOneWidget);
    expect(find.text('مرور یادداشت‌ها'), findsOneWidget);
    expect(
      find.descendant(of: workspace, matching: find.byType(SoftWell)),
      findsNothing,
    );
    expect(find.text('طبق ساعت'), findsNothing);
    expect(find.text('در صف انجام'), findsNothing);
    expect(find.text('دیرشده'), findsNothing);
    expect(find.text('زمان‌بندی‌شده'), findsNothing);
    expect(find.text('بدون ساعت'), findsNothing);
    expect(find.text('مرور روز'), findsNothing);
    expect(find.text('شروع تمرکز'), findsNothing);
    expect(find.text('۳ از ۴ انجام‌شده'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timed and untimed work share one contiguous list', (
    tester,
  ) async {
    api.seed(
      'inbox',
      'تماس ساعت‌دار',
      dates: TaskDates(
        due: TaskDue.at(
          DateTime(today.year, today.month, today.day, 9, 30),
          'Asia/Tehran',
        ),
      ),
    );
    await pump(tester);
    final workspace = find.byType(TodayWorkspace);
    expect(
      find.descendant(of: workspace, matching: find.text('تماس ساعت‌دار')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: workspace, matching: find.text('مرور یادداشت‌ها')),
      findsOneWidget,
    );
    expect(find.text('طبق ساعت'), findsNothing);
    expect(find.text('در صف انجام'), findsNothing);
    expect(find.text('۰۹:۳۰'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('تماس ساعت‌دار')).dy,
      lessThan(tester.getTopLeft(find.text('مرور یادداشت‌ها')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('late tasks stay inline and bulk reschedule remains possible', (
    tester,
  ) async {
    api.seed(
      'inbox',
      'کار عقب‌افتاده',
      dates: TaskDates(
        due: TaskDue.onDay(today.subtract(const Duration(days: 2))),
      ),
    );
    await pump(tester);
    expect(find.text('کار عقب‌افتاده'), findsOneWidget);
    expect(find.text('دیرشده'), findsNothing);
    await tester.ensureVisible(find.text('انتقال کارهای عقب‌افتاده به امروز'));
    await tester.tap(find.text('انتقال کارهای عقب‌افتاده به امروز'));
    await tester.pumpAndSettle();
    expect(api.byTitle('کار عقب‌افتاده').due, TaskDue.onDay(today));
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion reporting is not included in the task-only screen', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => throw StateError('offline'));
    expect(find.text('مرور یادداشت‌ها'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 375.0, 599.0, 600.0, 1200.0]) {
    testWidgets('flat Today renders at $width with large RTL text', (
      tester,
    ) async {
      await pump(
        tester,
        size: Size(width, 850),
        textScale: 2,
        dark: true,
        doneToday: () async => 1,
      );
      expect(find.byType(TodayWorkspace), findsOneWidget);
      expect(find.text('مرور یادداشت‌ها'), findsOneWidget);
      expect(find.text('در صف انجام'), findsNothing);
      expect(find.text('شروع تمرکز'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long unified list scrolls without hiding last task', (
    tester,
  ) async {
    for (var i = 2; i <= 12; i++) {
      api.seed(
        'inbox',
        'کار شماره $i',
        dates: TaskDates(due: TaskDue.onDay(today)),
      );
    }
    await pump(tester, size: const Size(375, 850), textScale: 2, dark: true);
    await tester.scrollUntilVisible(
      find.text('کار شماره 12'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('کار شماره 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
