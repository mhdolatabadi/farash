import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';
import 'package:farash/features/tasks/presentation/today_bento.dart';

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
        theme: dark ? FarashTheme.dark() : FarashTheme.light(),
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

  testWidgets('the tasks tile shows the server count of done tasks', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => 3);
    expect(find.byType(TodayBento), findsOneWidget);
    expect(find.text('۳ از ۴'), findsOneWidget);
    expect(find.byType(SoftWell), findsOneWidget);
  });

  testWidgets('without a server count the tile shows only open tasks', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('۱ باز'), findsOneWidget);
    expect(find.textContaining(' از '), findsNothing);
  });

  testWidgets('a failed count hides the progress instead of guessing', (
    tester,
  ) async {
    await pump(tester, doneToday: () async => throw StateError('offline'));
    expect(tester.takeException(), isNull);
    expect(find.text('۱ باز'), findsOneWidget);
  });

  testWidgets('the focus tile opens Focus', (tester) async {
    var opened = 0;
    await pump(tester, onOpenFocus: () => opened++);
    await tester.tap(find.bySemanticsLabel('باز کردن تمرکز'));
    expect(opened, 1);
  });

  testWidgets('narrow, dark and large text lay out without overflow', (
    tester,
  ) async {
    await pump(
      tester,
      doneToday: () async => 2,
      size: const Size(320, 760),
      textScale: 2,
      dark: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('مرور یادداشت‌ها'), findsOneWidget);
  });
}
