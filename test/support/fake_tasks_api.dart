import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

/// Tasks in memory, behaving like the API: soft delete with restore,
/// completed tasks hidden unless asked for, and order by sort_order.
class FakeTasksApi implements TasksApi {
  final _tasks = <Task>[];
  final _deleted = <String>{};
  int _nextId = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  /// Every reorder the app sent: (projectId, ids).
  final reorders = <(String, List<String>)>[];

  List<Task> get all => List.unmodifiable(_tasks);

  Task byTitle(String title) => _tasks.firstWhere((t) => t.title == title);

  bool isDeleted(String id) => _deleted.contains(id);

  /// Adds a task directly, as if another device had created it.
  Task seed(
    String projectId,
    String title, {
    TaskPriority priority = TaskPriority.p4,
    bool completed = false,
  }) {
    final task = Task(
      id: 't${_nextId++}',
      projectId: projectId,
      title: title,
      priority: priority,
      sortOrder: _tasks.where((t) => t.projectId == projectId).length,
      completedAt: completed ? DateTime(2026) : null,
    );
    _tasks.add(task);
    return task;
  }

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  Task _find(String id) {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0 || _deleted.contains(id)) {
      throw const ApiException(
        'not found',
        statusCode: 404,
        code: 'task_not_found',
      );
    }
    return _tasks[index];
  }

  void _replace(Task task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    _tasks[index] = task;
  }

  @override
  Future<List<Task>> listTasks(
    String token,
    String projectId, {
    bool showCompleted = false,
  }) async {
    _maybeFail();
    return [
      for (final t in _tasks)
        if (t.projectId == projectId &&
            !_deleted.contains(t.id) &&
            (showCompleted || !t.isCompleted))
          t,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<Task> createTask(String token, TaskDraft draft) async {
    _maybeFail();
    final task = Task(
      id: 't${_nextId++}',
      projectId: draft.projectId ?? 'inbox',
      title: draft.title!.trim(),
      description: draft.description ?? '',
      priority: draft.priority ?? TaskPriority.p4,
      sortOrder: draft.sortOrder ?? 0,
    );
    _tasks.add(task);
    return task;
  }

  @override
  Future<Task> updateTask(String token, String id, TaskDraft changes) async {
    _maybeFail();
    final updated = _find(id).copyWith(
      projectId: changes.projectId,
      title: changes.title?.trim(),
      description: changes.description,
      priority: changes.priority,
      sortOrder: changes.sortOrder,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Task> closeTask(String token, String id) async {
    _maybeFail();
    final task = _find(id);
    final closed = task.isCompleted
        ? task
        : task.copyWith(completedAt: DateTime(2026, 10, 1));
    _replace(closed);
    return closed;
  }

  @override
  Future<Task> reopenTask(String token, String id) async {
    _maybeFail();
    final reopened = _find(id).copyWith(clearCompletedAt: true);
    _replace(reopened);
    return reopened;
  }

  @override
  Future<void> deleteTask(String token, String id) async {
    _maybeFail();
    _find(id);
    _deleted.add(id);
  }

  @override
  Future<Task> restoreTask(String token, String id) async {
    _maybeFail();
    if (!_deleted.remove(id)) {
      throw const ApiException(
        'not found',
        statusCode: 404,
        code: 'task_not_found',
      );
    }
    return _find(id);
  }

  @override
  Future<void> reorderTasks(
    String token,
    String projectId,
    List<String> ids,
  ) async {
    _maybeFail();
    reorders.add((projectId, List.of(ids)));
    for (var i = 0; i < ids.length; i++) {
      _replace(_find(ids[i]).copyWith(sortOrder: i));
    }
  }
}
