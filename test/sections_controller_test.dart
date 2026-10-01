import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  late FakeTasksApi tasksApi;
  late FakeSectionsApi sectionsApi;
  late TasksController tasks;

  setUp(() {
    tasksApi = FakeTasksApi();
    sectionsApi = FakeSectionsApi(tasks: tasksApi);
    tasks = TasksController(
      api: tasksApi,
      sectionsApi: sectionsApi,
      token: () => 'token',
      projectId: 'p1',
    );
  });

  List<String> titlesIn(String? sectionId) => [
    for (final t in tasks.openIn(sectionId)) t.title,
  ];

  test('groups open tasks by section; a missing section falls back', () async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    sectionsApi.seed('p2', 'Other project');
    tasksApi.seed('p1', 'Loose');
    tasksApi.seed('p1', 'In backlog', sectionId: backlog.id);
    tasksApi.seed('p1', 'Orphan', sectionId: 'gone');

    await tasks.load();

    expect(tasks.sections.map((s) => s.name), ['Backlog']);
    expect(titlesIn(null), ['Loose', 'Orphan']);
    expect(titlesIn(backlog.id), ['In backlog']);
  });

  test('adding into a section sends section_id', () async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    await tasks.load();

    await tasks.add('A', sectionId: backlog.id);

    expect(titlesIn(backlog.id), ['A']);
    expect(tasksApi.byTitle('A').sectionId, backlog.id);
  });

  test('moveTask changes section and saves the new order', () async {
    final todo = sectionsApi.seed('p1', 'Todo');
    final done = sectionsApi.seed('p1', 'Doing');
    final a = tasksApi.seed('p1', 'A', sectionId: todo.id);
    final b = tasksApi.seed('p1', 'B', sectionId: done.id);
    await tasks.load();

    await tasks.moveTask(a, done.id, [b.id, a.id]);

    expect(titlesIn(todo.id), isEmpty);
    expect(titlesIn(done.id), ['B', 'A']);
    expect(tasksApi.byTitle('A').sectionId, done.id);
    expect(tasksApi.reorders.last.$2, [b.id, a.id]);

    // And out of every section.
    await tasks.moveTask(a, null, [a.id]);
    expect(titlesIn(null), ['A']);
    expect(tasksApi.byTitle('A').sectionId, isNull);
  });

  test('a failed move puts the task back', () async {
    final todo = sectionsApi.seed('p1', 'Todo');
    final a = tasksApi.seed('p1', 'A');
    await tasks.load();
    tasksApi.failNext = const ApiException('offline');

    await expectLater(
      tasks.moveTask(a, todo.id, [a.id]),
      throwsA(isA<ApiException>()),
    );
    expect(titlesIn(null), ['A']);
  });

  test('add, rename, collapse and reorder sections', () async {
    await tasks.load();
    final first = await tasks.addSection('  Todo ');
    final second = await tasks.addSection('Doing');

    await tasks.renameSection(first, 'To do');
    await tasks.setCollapsed(tasks.sectionById(second.id)!, true);
    await tasks.moveSection(tasks.sectionById(second.id)!, 0);

    expect(tasks.sections.map((s) => s.name), ['Doing', 'To do']);
    expect(tasks.sectionById(second.id)!.isCollapsed, isTrue);
    expect(sectionsApi.byName('Doing').sortOrder, 0);
  });

  test('a failed collapse rolls back', () async {
    final todo = sectionsApi.seed('p1', 'Todo');
    await tasks.load();
    sectionsApi.failNext = const ApiException('offline');

    await expectLater(
      tasks.setCollapsed(todo, true),
      throwsA(isA<ApiException>()),
    );
    expect(tasks.sectionById(todo.id)!.isCollapsed, isFalse);
  });

  test('deleting a section keeps or deletes its tasks', () async {
    final keep = sectionsApi.seed('p1', 'Keep');
    final drop = sectionsApi.seed('p1', 'Drop');
    tasksApi.seed('p1', 'Kept', sectionId: keep.id);
    final dropped = tasksApi.seed('p1', 'Dropped', sectionId: drop.id);
    await tasks.load();

    await tasks.deleteSection(keep, deleteTasks: false);
    expect(titlesIn(null), ['Kept']);

    await tasks.deleteSection(drop, deleteTasks: true);
    expect(tasks.tasks.map((t) => t.title), ['Kept']);
    expect(tasksApi.isDeleted(dropped.id), isTrue);
    expect(tasks.sections, isEmpty);
  });

  test('editing can move a task into or out of a section', () async {
    final todo = sectionsApi.seed('p1', 'Todo');
    final a = tasksApi.seed('p1', 'A');
    await tasks.load();

    await tasks.edit(
      a,
      title: 'A',
      description: '',
      priority: TaskPriority.p4,
      projectId: 'p1',
      sectionId: todo.id,
    );
    expect(tasksApi.byTitle('A').sectionId, todo.id);
    expect(titlesIn(todo.id), ['A']);

    await tasks.edit(
      tasks.openIn(todo.id).single,
      title: 'A',
      description: '',
      priority: TaskPriority.p4,
      projectId: 'p1',
    );
    expect(tasksApi.byTitle('A').sectionId, isNull);
  });

  test('without a sections API the project simply has none', () async {
    final plain = TasksController(
      api: tasksApi,
      token: () => 'token',
      projectId: 'p1',
    );
    tasksApi.seed('p1', 'A');
    await plain.load();

    expect(plain.sections, isEmpty);
    expect(plain.openIn(null).single.title, 'A');
  });

  test('Section and TaskDraft match the API JSON', () {
    final section = Section.fromJson({
      'id': 's1',
      'project_id': 'p1',
      'name': 'در حال انجام',
      'sort_order': 2,
      'is_collapsed': true,
      'created_at': '2026-10-01T00:00:00Z',
      'updated_at': '2026-10-01T00:00:00Z',
    });
    expect(section.isCollapsed, isTrue);
    expect(section.sortOrder, 2);
    expect(const TaskDraft(sectionId: '').toJson(), {'section_id': ''});
  });
}
