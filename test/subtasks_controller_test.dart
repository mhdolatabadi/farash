import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'support/fake_sections_api.dart';
import 'support/fake_tasks_api.dart';

void main() {
  late FakeTasksApi api;
  late FakeSectionsApi sectionsApi;
  late TasksController tasks;

  setUp(() {
    api = FakeTasksApi();
    sectionsApi = FakeSectionsApi(tasks: api);
    tasks = TasksController(
      api: api,
      sectionsApi: sectionsApi,
      token: () => 'token',
      projectId: 'p1',
    );
  });

  List<String> tree([String? section]) => [
    for (final (task, depth) in tasks.openTree(section))
      '${'  ' * depth}${task.title}',
  ];

  test('subtasks show under their parent, folded on request', () async {
    final trip = api.seed('p1', 'Trip');
    final tickets = api.seed('p1', 'Tickets', parent: trip);
    api.seed('p1', 'Seat', parent: tickets);
    api.seed('p1', 'Loose');
    await tasks.load();

    expect(tree(), ['Trip', '  Tickets', '    Seat', 'Loose']);
    expect(tasks.openIn(null).map((t) => t.title), ['Trip', 'Loose']);
    expect(tasks.taskById(trip.id)!.subtaskCount, 1);

    tasks.setFolded(tasks.taskById(trip.id)!, true);
    expect(tree(), ['Trip', 'Loose']);
    tasks.setFolded(tasks.taskById(trip.id)!, false);
    expect(tree(), hasLength(4));
  });

  test('a subtask follows its parent into a section', () async {
    final backlog = sectionsApi.seed('p1', 'Backlog');
    final trip = api.seed('p1', 'Trip', sectionId: backlog.id);
    await tasks.load();

    final sub = await tasks.add('Tickets', parent: tasks.taskById(trip.id));

    expect(sub.sectionId, backlog.id);
    expect(sub.parentId, trip.id);
    expect(tree(backlog.id), ['Trip', '  Tickets']);
    expect(tasks.taskById(trip.id)!.subtaskCount, 1);
  });

  test('closing a parent closes its subtasks; progress counts', () async {
    final trip = api.seed('p1', 'Trip');
    final tickets = api.seed('p1', 'Tickets', parent: trip);
    api.seed('p1', 'Hotel', parent: trip);
    await tasks.load();

    await tasks.setCompleted(tasks.taskById(tickets.id)!, true);
    expect(tasks.taskById(trip.id)!.completedSubtaskCount, 1);
    expect(tree(), ['Trip', '  Hotel']);

    await tasks.setCompleted(tasks.taskById(trip.id)!, true);
    expect(tree(), isEmpty);
    expect(api.byTitle('Hotel').isCompleted, isTrue);

    // Undo brings back the parent with the subtask that closed with it.
    await tasks.setCompleted(trip, false);
    expect(tree(), ['Trip', '  Hotel']);
  });

  test('reopening a subtask reopens its parent', () async {
    final trip = api.seed('p1', 'Trip');
    final tickets = api.seed('p1', 'Tickets', parent: trip);
    await tasks.load();
    await tasks.setCompleted(tasks.taskById(trip.id)!, true);
    await tasks.setShowCompleted(true);

    await tasks.setCompleted(tasks.taskById(tickets.id)!, false);

    expect(api.byTitle('Trip').isCompleted, isFalse);
    expect(tree(), ['Trip', '  Tickets']);
  });

  test('deleting a parent deletes its subtasks; undo restores them', () async {
    final trip = api.seed('p1', 'Trip');
    final tickets = api.seed('p1', 'Tickets', parent: trip);
    api.seed('p1', 'Seat', parent: tickets);
    await tasks.load();

    await tasks.delete(tasks.taskById(trip.id)!);
    expect(tasks.tasks, isEmpty);
    expect(api.isDeleted(tickets.id), isTrue);

    await tasks.undoDelete(trip);
    expect(tree(), ['Trip', '  Tickets', '    Seat']);
  });

  test('deleting a subtask updates the parent\'s count', () async {
    final trip = api.seed('p1', 'Trip');
    final tickets = api.seed('p1', 'Tickets', parent: trip);
    await tasks.load();

    await tasks.delete(tasks.taskById(tickets.id)!);
    expect(tasks.taskById(trip.id)!.subtaskCount, 0);
  });

  test('indent nests under the task above; outdent lifts a level', () async {
    final a = api.seed('p1', 'A');
    final b = api.seed('p1', 'B');
    api.seed('p1', 'C');
    await tasks.load();

    expect(tasks.indentTarget(tasks.taskById(a.id)!), isNull);
    await tasks.indent(tasks.taskById(b.id)!);
    expect(tree(), ['A', '  B', 'C']);
    expect(api.byTitle('B').parentId, a.id);

    await tasks.outdent(tasks.taskById(b.id)!);
    expect(tree(), ['A', 'B', 'C']);
    expect(api.byTitle('B').parentId, isNull);
    expect(api.reorders.last.$2, [a.id, b.id, api.byTitle('C').id]);
  });

  test('a task cannot move under its own subtask', () async {
    final a = api.seed('p1', 'A');
    final b = api.seed('p1', 'B', parent: a);
    await tasks.load();

    await tasks.moveTask(tasks.taskById(a.id)!, null, [
      a.id,
    ], parent: tasks.taskById(b.id));
    expect(api.byTitle('A').parentId, isNull);
    expect(api.reorders, isEmpty);
  });

  test('a refused move rolls back', () async {
    final a = api.seed('p1', 'A');
    final b = api.seed('p1', 'B');
    await tasks.load();
    api.failNext = const ApiException(
      'invalid',
      statusCode: 400,
      code: 'invalid_parent',
    );

    await expectLater(
      tasks.indent(tasks.taskById(b.id)!),
      throwsA(isA<ApiException>()),
    );
    expect(tree(), ['A', 'B']);
    expect(tasks.taskById(a.id)!.subtaskCount, 0);
  });

  test('ticking a checklist item saves the description', () async {
    final a = api.seed('p1', 'A');
    await tasks.load();
    await tasks.saveDescription(a, '- [x] نان');
    expect(api.byTitle('A').description, '- [x] نان');
    expect(tasks.taskById(a.id)!.description, '- [x] نان');
  });

  test('Task and TaskDraft carry the subtask fields', () {
    final task = Task.fromJson({
      'id': 't2',
      'project_id': 'p1',
      'parent_id': 't1',
      'title': 'زیرکار',
      'subtask_count': 5,
      'completed_subtask_count': 2,
    });
    expect(task.parentId, 't1');
    expect(task.hasSubtasks, isTrue);
    expect(task.completedSubtaskCount, 2);
    expect(const TaskDraft(parentId: '').toJson(), {'parent_id': ''});
  });
}
