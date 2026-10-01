import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'support/fake_tasks_api.dart';

class DeferredTasksApi extends FakeTasksApi {
  final loads = <Completer<List<Task>>>[];
  Completer<Task>? creation;

  @override
  Future<List<Task>> listTasks(
    String token,
    String projectId, {
    bool showCompleted = false,
  }) {
    final response = Completer<List<Task>>();
    loads.add(response);
    return response.future;
  }

  @override
  Future<Task> createTask(String token, TaskDraft draft) {
    return (creation = Completer<Task>()).future;
  }
}

void main() {
  late DeferredTasksApi api;
  late TasksController tasks;
  String? session;
  const task = Task(id: 't1', projectId: 'p1', title: 'Current');

  setUp(() {
    api = DeferredTasksApi();
    session = 'token';
    tasks = TasksController(api: api, token: () => session, projectId: 'p1');
  });

  test('older load cannot replace newer visibility results', () async {
    final older = tasks.load();
    final newer = tasks.setShowCompleted(true);
    api.loads[1].complete([task]);
    await newer;
    api.loads[0].complete([]);
    await older;
    expect(tasks.tasks, [task]);
    expect(tasks.isLoading, isFalse);
    expect(tasks.error, isNull);
    tasks.dispose();
  });

  test('older failure cannot end or fail a newer load', () async {
    final older = tasks.load();
    final newer = tasks.load();
    api.loads[0].completeError(StateError('old failure'));
    await older;
    expect(tasks.isLoading, isTrue);
    expect(tasks.error, isNull);
    api.loads[1].complete([task]);
    await newer;
    expect(tasks.tasks, [task]);
    tasks.dispose();
  });

  test('sign-out discards an in-flight response', () async {
    final pending = tasks.load();
    session = null;
    api.loads.single.complete([task]);
    await pending;
    expect(tasks.tasks, isEmpty);
    tasks.dispose();
  });

  for (final fails in [false, true]) {
    test('load after disposal is safe (failure: $fails)', () async {
      final pending = tasks.load();
      tasks.dispose();
      if (fails) {
        api.loads.single.completeError(StateError('late failure'));
      } else {
        api.loads.single.complete([task]);
      }
      await pending;
      expect(tasks.tasks, isEmpty);
    });

    test(
      'write after disposal preserves its result (failure: $fails)',
      () async {
        final pending = tasks.add('Current');
        tasks.dispose();
        if (fails) {
          final expectation = expectLater(pending, throwsStateError);
          api.creation!.completeError(StateError('late failure'));
          await expectation;
        } else {
          api.creation!.complete(task);
          expect(await pending, task);
        }
      },
    );
  }
}
