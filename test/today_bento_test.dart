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

  testWidgets('Today is a task-first workspace, not three summary tiles', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => 3);
    final workspace = find.byType(TodayWorkspace);
    expect(workspace, findsOneWidget);
    expect(
      find.descendant(of: workspace, matching: find.byType(SoftWell)),
      findsNothing,
    );
    expect(find.text('در صف انجام'), findsOneWidget);
    expect(find.text('مرور یادداشت‌ها'), findsOneWidget);
    expect(find.text('۳ از ۴ انجام‌شده'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no server statistics means no invented completion progress', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('۱ کار باقی‌مانده'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server statistics failure leaves only the real open count', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => throw StateError('offline'));
    expect(find.text('۱ کار باقی‌مانده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion stats retain Persian screen-reader semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, doneToday: () async => 3);
    await tester.ensureVisible(find.text('۳ از ۴ انجام‌شده'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('۳ کار از ۴ کار امروز انجام شد'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('focus is a real reachable secondary action', (tester) async {
    var opened = 0;
    await pump(tester, onOpenFocus: () => opened++);
    final shortcut = find.text('شروع تمرکز');
    await tester.ensureVisible(shortcut);
    await tester.pumpAndSettle();
    await tester.tap(shortcut);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timed tasks use a clock lane and other tasks stay flexible', (
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
    expect(find.text('طبق ساعت'), findsOneWidget);
    expect(find.text('در صف انجام'), findsOneWidget);
    expect(find.text('تماس ساعت‌دار'), findsOneWidget);
    expect(find.text('۰۹:۳۰'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overdue work is a separate lane with a real bulk action', (
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
    expect(find.text('دیرشده'), findsOneWidget);
    expect(find.text('کار عقب‌افتاده'), findsOneWidget);
    await tester.ensureVisible(find.text('انتقال همه به امروز'));
    await tester.tap(find.text('انتقال همه به امروز'));
    await tester.pumpAndSettle();
    expect(find.text('دیرشده'), findsNothing);
    expect(api.byTitle('کار عقب‌افتاده').due, TaskDue.onDay(today));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 375.0, 599.0, 600.0]) {
    testWidgets('mobile workspace at $width with large RTL text', (
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
      expect(find.text('در صف انجام'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop has two columns instead of stretched mobile cards', (
    tester,
  ) async {
    await pump(tester, size: const Size(1200, 900));
    final taskColumn = find.text('در صف انجام');
    final companion = find.text('مرور روز');
    expect(taskColumn, findsOneWidget);
    expect(companion, findsOneWidget);
    expect(
      (tester.getTopLeft(taskColumn).dx - tester.getTopLeft(companion).dx)
          .abs(),
      greaterThan(120),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'twelve tasks still scroll to the last without covering capture',
    (tester) async {
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
    },
  );
}
