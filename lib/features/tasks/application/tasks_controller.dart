import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

/// The tasks of one project. Changes show at once and roll back when the API
/// refuses them.
class TasksController extends ChangeNotifier {
  TasksController({
    required TasksApi api,
    required this.token,
    required this.projectId,
  }) : _api = api;

  final TasksApi _api;
  final String? Function() token;
  final String projectId;

  List<Task> _tasks = const [];
  bool _loading = false;
  bool _showCompleted = false;
  Object? _error;

  /// Open tasks in their order, then completed ones when they are shown.
  List<Task> get tasks => [...openTasks, ...completedTasks];

  List<Task> get openTasks => [
    for (final t in _tasks)
      if (!t.isCompleted) t,
  ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Task> get completedTasks => _showCompleted
      ? [
          for (final t in _tasks)
            if (t.isCompleted) t,
        ]
      : const [];

  bool get isLoading => _loading;
  bool get showCompleted => _showCompleted;

  /// The last load failure, shown with a retry action.
  Object? get error => _error;

  Future<void> load() async {
    final token = this.token();
    if (token == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _tasks = await _api.listTasks(
        token,
        projectId,
        showCompleted: _showCompleted,
      );
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setShowCompleted(bool show) async {
    if (show == _showCompleted) return;
    _showCompleted = show;
    await load();
  }

  /// Adds a task at the end of the open list.
  Future<Task> add(
    String title, {
    TaskPriority priority = TaskPriority.p4,
  }) async {
    final open = openTasks;
    final task = await _api.createTask(
      _requireToken(),
      TaskDraft(
        projectId: projectId,
        title: title.trim(),
        priority: priority,
        sortOrder: open.isEmpty ? 0 : open.last.sortOrder + 1,
      ),
    );
    _tasks = [..._tasks, task];
    notifyListeners();
    return task;
  }

  /// Saves edits from the detail sheet. A task moved to another project
  /// leaves this list.
  Future<void> edit(
    Task task, {
    required String title,
    required String description,
    required TaskPriority priority,
    required String projectId,
  }) async {
    final moved = projectId != this.projectId;
    final updated = await _api.updateTask(
      _requireToken(),
      task.id,
      TaskDraft(
        title: title.trim(),
        description: description,
        priority: priority,
        projectId: moved ? projectId : null,
      ),
    );
    _tasks = [
      for (final t in _tasks)
        if (t.id != task.id) t else if (!moved) updated,
    ];
    notifyListeners();
  }

  /// Checks a task off, or back on. Calling it again with the opposite value
  /// is the undo.
  Future<void> setCompleted(Task task, bool completed) async {
    final before = _tasks;
    final now = DateTime.now();
    _tasks = [
      for (final t in _tasks)
        if (t.id != task.id)
          t
        else
          completed
              ? t.copyWith(completedAt: now)
              : t.copyWith(clearCompletedAt: true),
    ];
    // An undo of a hidden completion puts the task back in the list.
    if (!completed && !_tasks.any((t) => t.id == task.id)) {
      _tasks = [..._tasks, task.copyWith(clearCompletedAt: true)];
    }
    notifyListeners();
    try {
      final token = _requireToken();
      final saved = completed
          ? await _api.closeTask(token, task.id)
          : await _api.reopenTask(token, task.id);
      _tasks = [
        for (final t in _tasks)
          if (t.id != saved.id) t else saved,
      ];
      if (completed && !_showCompleted) {
        _tasks = [
          for (final t in _tasks)
            if (t.id != saved.id) t,
        ];
      }
      notifyListeners();
    } catch (_) {
      _tasks = before;
      notifyListeners();
      rethrow;
    }
  }

  /// Removes a task; [undoDelete] restores it.
  Future<void> delete(Task task) async {
    final before = _tasks;
    _tasks = [
      for (final t in _tasks)
        if (t.id != task.id) t,
    ];
    notifyListeners();
    try {
      await _api.deleteTask(_requireToken(), task.id);
    } catch (_) {
      _tasks = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> undoDelete(Task task) async {
    final restored = await _api.restoreTask(_requireToken(), task.id);
    if (restored.projectId == projectId &&
        (!restored.isCompleted || _showCompleted)) {
      _tasks = [..._tasks, restored];
      notifyListeners();
    }
  }

  /// Moves the open task at [oldIndex] so that it ends up at [newIndex]
  /// among the open tasks.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final open = openTasks;
    if (oldIndex < 0 || oldIndex >= open.length) return;
    if (newIndex == oldIndex) return;
    final moved = open.removeAt(oldIndex);
    open.insert(newIndex.clamp(0, open.length), moved);

    final before = _tasks;
    final order = {for (var i = 0; i < open.length; i++) open[i].id: i};
    _tasks = [
      for (final t in _tasks)
        order.containsKey(t.id) ? t.copyWith(sortOrder: order[t.id]) : t,
    ];
    notifyListeners();
    try {
      await _api.reorderTasks(_requireToken(), projectId, [
        for (final t in open) t.id,
      ]);
    } catch (_) {
      _tasks = before;
      notifyListeners();
      rethrow;
    }
  }

  String _requireToken() {
    final token = this.token();
    if (token == null) {
      throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.');
    }
    return token;
  }
}
