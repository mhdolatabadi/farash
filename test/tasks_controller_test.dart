import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'support/fake_tasks_api.dart';

void main() {
  late FakeTasksApi api;
  late TasksController tasks;

  setUp(() {
    api = FakeTasksApi();
    tasks = TasksController(api: api, token: () => 'token', projectId: 'p1');
  });

  List<String> titles() => [for (final t in tasks.tasks) t.title];

  test('loads only this project, open tasks in order', () async {
    api.seed('p1', 'A');
    api.seed('p2', 'Elsewhere');
    api.seed('p1', 'Done', completed: true);
    api.seed('p1', 'B');

    await tasks.load();

    expect(titles(), ['A', 'B']);
  });

  test('add puts the task at the end with its priority', () async {
    await tasks.load();
    await tasks.add('  First ');
    await tasks.add('Urgent', priority: TaskPriority.p1);

    expect(titles(), ['First', 'Urgent']);
    expect(api.byTitle('Urgent').priority, TaskPriority.p1);
    expect(api.byTitle('Urgent').sortOrder, 1);
  });

  test('completing hides the task; undo brings it back', () async {
    final a = api.seed('p1', 'A');
    await tasks.load();

    await tasks.setCompleted(a, true);
    expect(titles(), isEmpty);
    expect(api.byTitle('A').isCompleted, isTrue);

    await tasks.setCompleted(a, false);
    expect(titles(), ['A']);
    expect(api.byTitle('A').isCompleted, isFalse);
  });

  test('with completed shown, a completed task moves below', () async {
    final a = api.seed('p1', 'A');
    api.seed('p1', 'B');
    await tasks.setShowCompleted(true);

    await tasks.setCompleted(a, true);

    expect(titles(), ['B', 'A']);
    expect(tasks.completedTasks.single.title, 'A');
  });

  test('a failed completion rolls back', () async {
    final a = api.seed('p1', 'A');
    await tasks.load();
    api.failNext = const ApiException('offline');

    await expectLater(
      tasks.setCompleted(a, true),
      throwsA(isA<ApiException>()),
    );
    expect(titles(), ['A']);
    expect(tasks.tasks.single.isCompleted, isFalse);
  });

  test('delete and undo restore the same task', () async {
    final a = api.seed('p1', 'A');
    await tasks.load();

    await tasks.delete(a);
    expect(titles(), isEmpty);
    expect(api.isDeleted(a.id), isTrue);

    await tasks.undoDelete(a);
    expect(titles(), ['A']);
    expect(api.isDeleted(a.id), isFalse);
  });

  test('a failed delete keeps the task', () async {
    final a = api.seed('p1', 'A');
    await tasks.load();
    api.failNext = const ApiException('offline');

    await expectLater(tasks.delete(a), throwsA(isA<ApiException>()));
    expect(titles(), ['A']);
  });

  test('reorder sends the full open order', () async {
    api.seed('p1', 'A');
    api.seed('p1', 'B');
    api.seed('p1', 'C');
    await tasks.load();

    await tasks.reorder(2, 0);

    expect(titles(), ['C', 'A', 'B']);
    expect(api.reorders.single.$1, 'p1');
    expect(api.reorders.single.$2, ['t3', 't1', 't2']);
  });

  test('a failed reorder puts the list back', () async {
    api.seed('p1', 'A');
    api.seed('p1', 'B');
    await tasks.load();
    api.failNext = const ApiException('offline');

    await expectLater(tasks.reorder(0, 1), throwsA(isA<ApiException>()));
    expect(titles(), ['A', 'B']);
  });

  test('editing saves fields; moving removes the task here', () async {
    final a = api.seed('p1', 'A');
    final b = api.seed('p1', 'B');
    await tasks.load();

    await tasks.edit(
      a,
      title: 'A2',
      description: '# notes',
      priority: TaskPriority.p2,
      projectId: 'p1',
    );
    expect(api.byTitle('A2').description, '# notes');
    expect(tasks.tasks.first.priority, TaskPriority.p2);

    await tasks.edit(
      b,
      title: 'B',
      description: '',
      priority: TaskPriority.p4,
      projectId: 'p2',
    );
    expect(titles(), ['A2']);
    expect(api.byTitle('B').projectId, 'p2');
  });

  test('without a token nothing is sent', () async {
    final signedOut = TasksController(
      api: api,
      token: () => null,
      projectId: 'p1',
    );
    await signedOut.load();
    expect(signedOut.tasks, isEmpty);
    await expectLater(signedOut.add('x'), throwsA(isA<ApiException>()));
  });

  test('Task and TaskDraft match the API JSON', () {
    final task = Task.fromJson({
      'id': 't1',
      'project_id': 'p1',
      'title': 'خرید نان',
      'description': '',
      'priority': 1,
      'sort_order': 2,
      'completed_at': '2026-10-01T08:00:00Z',
      'created_at': '2026-10-01T07:00:00Z',
      'updated_at': '2026-10-01T08:00:00Z',
    });
    expect(task.priority, TaskPriority.p1);
    expect(task.isCompleted, isTrue);

    expect(const TaskDraft(title: 'x', priority: TaskPriority.p2).toJson(), {
      'title': 'x',
      'priority': 2,
    });
    expect(TaskPriority.fromLevel(9), TaskPriority.p4);
  });
}
