import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';
import 'package:menval/features/projects/data/project.dart';
import 'package:menval/features/search/filter_editor.dart';
import 'package:menval/features/search/search.dart';
import 'package:menval/features/search/search_view.dart';
import 'package:menval/features/tasks/data/task.dart';

import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

class _Filters implements SearchApi {
  final saved = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (method == 'POST') {
      final filter = {'id': 'f${saved.length}', ...body!};
      saved.add(filter);
      return {'filter': filter};
    }
    return {'filters': saved};
  }
}

Task _task(
  String id, {
  String? due,
  int priority = 4,
  List<String> labels = const [],
  String project = 'a',
}) => Task.fromJson({
  'id': id,
  'project_id': project,
  'title': id,
  'priority': priority,
  'sort_order': 0,
  'label_ids': labels,
  if (due != null) 'due': {'date': due},
});

class _SearchingTasks extends FakeTasksApi implements SearchApi {
  final filters = <Map<String, Object?>>[
    {
      'id': 'f1',
      'name': 'تماس‌ها',
      'query': '@تلفن',
      'sort': 'priority',
      'group_by': 'project',
      'is_favorite': true,
      'color': '#2563EB',
    },
  ];
  final searches = <Uri>[];
  @override
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/api/v1/search') {
      searches.add(uri);
      return {'tasks': [], 'has_more': false};
    }
    return {'filters': filters};
  }
}

void main() {
  testWidgets('saved filters sit in the sidebar and open with their settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tasks = _SearchingTasks();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(
            email: 'a@example.com',
            onLogout: () {},
            projects: ProjectsController(
              api: FakeProjectsApi(),
              token: () => 'token',
            ),
            tasksApi: tasks,
            token: () => 'token',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('فیلترها'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filter-f1')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'تماس‌ها'), findsOneWidget);
    expect(tasks.searches.last.queryParameters['q'], '@تلفن');
    expect(tasks.searches.last.queryParameters['sort'], 'priority');
    expect(find.text('گروه: پروژه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('a smart list form becomes the search query language', () {
    expect(const SmartListForm().toQuery(), '');
    expect(
      const SmartListForm(
        dates: {'today', 'overdue'},
        priorities: {2, 1},
        projects: ['کار شخصی'],
        labels: ['تلفن'],
        text: 'امروز',
      ).toQuery(),
      '(today | overdue) & (p1 | p2) & #"کار شخصی" & @تلفن & "امروز"',
    );
    expect(
      const SmartListForm(dates: {'7days'}, priorities: {1}).toQuery(),
      '7 days & p1',
    );
    expect(const SmartListForm(dates: {'nodate'}).toQuery(), 'no date');
  });

  test('results group by date, priority, project and label in order', () {
    final today = DateTime(2026, 11, 14);
    final tasks = [
      _task('later', due: '2026-12-30', priority: 1, labels: ['l1']),
      _task('none', priority: 3, project: 'b'),
      _task('late', due: '2026-11-10', priority: 1, labels: ['l1', 'l2']),
      _task('now', due: '2026-11-14', priority: 2),
    ];
    String titles(String group) => groupTasks(
      tasks,
      group,
      today: today,
      projects: const [
        Project(id: 'a', name: 'الف', color: '#7c3aed'),
        Project(id: 'b', name: 'ب', color: '#7c3aed'),
      ],
      labelName: (id) => {'l1': 'خانه', 'l2': 'تلفن'}[id],
    ).map((g) => '${g.$1}:${g.$2.map((t) => t.id).join(',')}').join(' ');

    expect(titles('none'), 'null:later,none,late,now');
    expect(titles('date'), 'دیرشده:late امروز:now بعدتر:later بی‌تاریخ:none');
    expect(
      titles('priority'),
      'اولویت ۱:later,late اولویت ۲:now اولویت ۳:none',
    );
    expect(titles('project'), 'الف:later,late,now ب:none');
    // A task with two labels appears under each.
    expect(titles('label'), '@تلفن:late @خانه:later,late بدون برچسب:none,now');
  });

  testWidgets('the filter editor builds a query from the form and saves it', (
    tester,
  ) async {
    final api = _Filters();
    final controller = FiltersController(api: api, token: () => 't');
    SavedFilter? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showFilterEditor(
              context,
              controller: controller,
              projectNames: const ['کار'],
              labelNames: const ['تلفن'],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'نام فیلتر'),
      'تماس‌های امروز',
    );
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'امروز'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, '@تلفن'));
    await tester.pump();
    expect(find.text('today & @تلفن'), findsOneWidget);
    await tester.tap(find.text('بدون گروه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('برچسب').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ذخیره'));
    await tester.pumpAndSettle();
    expect(api.saved.single['query'], 'today & @تلفن');
    expect(api.saved.single['group_by'], 'label');
    expect(api.saved.single['is_favorite'], true);
    expect(result?.name, 'تماس‌های امروز');
    expect(controller.filters.single.id, 'f0');
  });
}
