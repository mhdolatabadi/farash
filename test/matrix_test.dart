import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/matrix/matrix.dart';
import 'package:farash/features/matrix/matrix_view.dart';
import 'package:farash/features/search/search.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'support/fake_tasks_api.dart';

/// Answers each quadrant's default rule from the fake's tasks.
class _MatrixApi extends FakeTasksApi implements SearchApi {
  final queries = <String>[];
  @override
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse(path);
    final q = uri.queryParameters['q']!;
    queries.add(q);
    final today = DateTime.now();
    final quadrant = Quadrant.values
        .where((x) => x.defaultRule == q)
        .firstOrNull;
    final all = this.all.where((t) => !t.isCompleted && t.parentId == null);
    return {
      'tasks': [
        for (final t in all)
          if (quadrant != null &&
              (t.priority.level <= 2) == quadrant.important &&
              (t.due != null &&
                      !t.due!.day.isAfter(
                        DateTime(today.year, today.month, today.day),
                      )) ==
                  quadrant.urgent)
            {
              'id': t.id,
              'project_id': t.projectId,
              'title': t.title,
              'priority': t.priority.level,
              'sort_order': 0,
              if (t.due != null) 'due': {'date': t.due!.date},
            },
      ],
      'has_more': false,
    };
  }
}

Task _task({int priority = 4, DateTime? due}) => Task.fromJson({
  'id': 'x',
  'project_id': 'p',
  'title': 'x',
  'priority': priority,
  'sort_order': 0,
  if (due != null) 'due': {'date': dateKeyFor(due)},
});

String dateKeyFor(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final now = DateTime(2026, 11, 14, 9);

  test('default rules split by priority and due date', () {
    expect(Quadrant.doFirst.defaultRule, '(p1 | p2) & (overdue | today)');
    expect(Quadrant.later.defaultRule, '(p3 | p4) & !(overdue | today)');
  });

  test('moving into a quadrant changes only what differs', () {
    final later = _task(priority: 4);
    final first = moveIntoQuadrant(later, Quadrant.doFirst, now: now)!;
    expect(first.priority, TaskPriority.p1);
    expect(first.dates!.due!.date, '2026-11-14');

    final urgentImportant = _task(priority: 1, due: DateTime(2026, 11, 10));
    final scheduled = moveIntoQuadrant(
      urgentImportant,
      Quadrant.schedule,
      now: now,
    )!;
    expect(scheduled.priority, isNull);
    expect(scheduled.dates!.due!.date, '2026-11-15');

    final delegated = moveIntoQuadrant(
      urgentImportant,
      Quadrant.delegate,
      now: now,
    )!;
    expect(delegated.priority, TaskPriority.p4);
    expect(delegated.dates, isNull);

    expect(
      moveIntoQuadrant(urgentImportant, Quadrant.doFirst, now: now),
      isNull,
    );
  });

  test('rules are kept per device and reset to the default', () async {
    final store = MemoryCalendarSettingsStore();
    final rules = MatrixRules(store: store);
    await rules.setRule(Quadrant.doFirst, 'p1 & @کار');
    final again = MatrixRules(store: store);
    await again.load();
    expect(again.rule(Quadrant.doFirst), 'p1 & @کار');
    await again.setRule(Quadrant.doFirst, '');
    expect(again.isDefault(Quadrant.doFirst), isTrue);
    expect(store.values['matrix_rule_doFirst'], '');
  });

  testWidgets('quadrants list tasks, and dragging one moves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _MatrixApi();
    final task = api.seed('work', 'گزارش فصل', priority: TaskPriority.p1);
    api.seed('work', 'خرید', priority: TaskPriority.p4);
    final rules = MatrixRules(store: MemoryCalendarSettingsStore());
    await tester.pumpWidget(
      MaterialApp(
        home: MatrixView(
          search: api,
          tasks: api,
          token: () => 't',
          projects: () => const [],
          rules: rules,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder inQuadrant(Quadrant q, String text) => find.descendant(
      of: find.byKey(ValueKey('quadrant-${q.name}')),
      matching: find.text(text),
    );
    expect(inQuadrant(Quadrant.schedule, 'گزارش فصل'), findsOneWidget);
    expect(inQuadrant(Quadrant.later, 'خرید'), findsOneWidget);

    final start = tester.getCenter(inQuadrant(Quadrant.schedule, 'گزارش فصل'));
    final end = tester.getCenter(
      find.byKey(const ValueKey('quadrant-doFirst')),
    );
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(start, end, i / 10)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(inQuadrant(Quadrant.doFirst, 'گزارش فصل'), findsOneWidget);
    expect(api.all.firstWhere((t) => t.id == task.id).due, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phones stack the quadrants without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _MatrixApi();
    for (var i = 0; i < 6; i++) {
      api.seed(
        'work',
        'کار بسیار بسیار طولانی شمارهٔ $i برای آزمودن شکستن خط',
        priority: TaskPriority.p2,
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MatrixView(
            search: api,
            tasks: api,
            token: () => 't',
            projects: () => const [],
            rules: MatrixRules(store: MemoryCalendarSettingsStore()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('نه فوری نه مهم'), 300);
    expect(find.text('نه فوری نه مهم'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
