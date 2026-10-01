import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

/// Tasks in memory, behaving like the API: soft delete with restore,
/// completed tasks hidden unless asked for, order by sort_order, and
/// subtasks that close, delete and move with their parent.
class FakeTasksApi implements TasksApi {
  final _tasks = <Task>[];
  final _deleted = <String>{};
  int _nextId = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  /// Every reorder the app sent: (projectId, ids).
  final reorders = <(String, List<String>)>[];

  List<Task> get all => List.unmodifiable(_tasks);

  Task byTitle(String title) =>
      _counted(_tasks.firstWhere((t) => t.title == title));

  bool isDeleted(String id) => _deleted.contains(id);

  /// Adds a task directly, as if another device had created it.
  Task seed(
    String projectId,
    String title, {
    TaskPriority priority = TaskPriority.p4,
    bool completed = false,
    String? sectionId,
    Task? parent,
  }) {
    final task = Task(
      id: 't${_nextId++}',
      projectId: projectId,
      sectionId: parent?.sectionId ?? sectionId,
      parentId: parent?.id,
      title: title,
      priority: priority,
      sortOrder: _tasks.where((t) => t.projectId == projectId).length,
      completedAt: completed ? DateTime(2026) : null,
    );
    _tasks.add(task);
    return task;
  }

  /// Live tasks below [id], deleted ones too when [withDeleted].
  List<Task> _below(String id, {bool withDeleted = false}) {
    final found = <Task>[];
    var level = {id};
    while (level.isNotEmpty) {
      final next = [
        for (final t in _tasks)
          if (level.contains(t.parentId) &&
              (withDeleted || !_deleted.contains(t.id)))
            t,
      ];
      found.addAll(next);
      level = {for (final t in next) t.id};
    }
    return found;
  }

  /// The task with its subtask counts, as the API reports them.
  Task _counted(Task task) {
    final children = [
      for (final t in _tasks)
        if (t.parentId == task.id && !_deleted.contains(t.id)) t,
    ];
    return task.copyWith(
      subtaskCount: children.length,
      completedSubtaskCount: children.where((t) => t.isCompleted).length,
    );
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
          _counted(t),
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<Task> createTask(String token, TaskDraft draft) async {
    _maybeFail();
    final parent = draft.parentId == null ? null : _find(draft.parentId!);
    final task = Task(
      id: 't${_nextId++}',
      projectId: parent?.projectId ?? draft.projectId ?? 'inbox',
      sectionId: parent == null ? draft.sectionId : parent.sectionId,
      parentId: parent?.id,
      title: draft.title!.trim(),
      description: draft.description ?? '',
      priority: draft.priority ?? TaskPriority.p4,
      sortOrder: draft.sortOrder ?? 0,
    );
    _tasks.add(task);
    return _counted(task);
  }

  @override
  Future<Task> updateTask(String token, String id, TaskDraft changes) async {
    _maybeFail();
    final current = _find(id);
    // Like the API: "" leaves the section, a new project drops it.
    final leaveSection =
        changes.sectionId == '' ||
        (changes.projectId != null &&
            changes.projectId != current.projectId &&
            changes.sectionId == null);
    var updated = current.copyWith(
      sectionId: changes.sectionId == '' ? null : changes.sectionId,
      clearSection: leaveSection,
      projectId: changes.projectId,
      title: changes.title?.trim(),
      description: changes.description,
      priority: changes.priority,
      sortOrder: changes.sortOrder,
    );
    // Like the API: a parent_id nests the task in the parent's place; "" or
    // a move elsewhere on its own makes it top-level.
    if (changes.parentId case final parentId? when parentId != '') {
      final parent = _find(parentId);
      if (parent.id == id || _below(id).any((t) => t.id == parent.id)) {
        throw const ApiException(
          'invalid',
          statusCode: 400,
          code: 'invalid_parent',
        );
      }
      updated = updated.copyWith(
        parentId: parent.id,
        projectId: parent.projectId,
        sectionId: parent.sectionId,
        clearSection: parent.sectionId == null,
      );
    } else if (changes.parentId == '' ||
        updated.projectId != current.projectId ||
        updated.sectionId != current.sectionId) {
      updated = updated.copyWith(clearParent: true);
    }
    _replace(updated);
    for (final t in _below(id, withDeleted: true)) {
      _replace(
        t.copyWith(
          projectId: updated.projectId,
          sectionId: updated.sectionId,
          clearSection: updated.sectionId == null,
        ),
      );
    }
    return _counted(updated);
  }

  @override
  Future<Task> closeTask(String token, String id) async {
    _maybeFail();
    final task = _find(id);
    final at = task.completedAt ?? DateTime(2026, 10, 1, 0, 0, _nextId++);
    _replace(task.copyWith(completedAt: at));
    for (final t in _below(id)) {
      if (!t.isCompleted) _replace(t.copyWith(completedAt: at));
    }
    return _counted(_find(id));
  }

  @override
  Future<Task> reopenTask(String token, String id) async {
    _maybeFail();
    final task = _find(id);
    final at = task.completedAt;
    _replace(task.copyWith(clearCompletedAt: true));
    for (final t in _below(id)) {
      if (at != null && t.completedAt == at) {
        _replace(t.copyWith(clearCompletedAt: true));
      }
    }
    var parentId = task.parentId;
    while (parentId != null) {
      final parent = _tasks.firstWhere((t) => t.id == parentId);
      _replace(parent.copyWith(clearCompletedAt: true));
      parentId = parent.parentId;
    }
    return _counted(_find(id));
  }

  /// When each task was deleted, so a restore brings back its subtree.
  final _deletedWith = <String, String>{};

  @override
  Future<void> deleteTask(String token, String id) async {
    _maybeFail();
    _find(id);
    for (final t in _below(id)) {
      _deleted.add(t.id);
      _deletedWith[t.id] = id;
    }
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
    for (final entry in [..._deletedWith.entries]) {
      if (entry.value == id) {
        _deleted.remove(entry.key);
        _deletedWith.remove(entry.key);
      }
    }
    final task = _find(id);
    if (task.parentId != null && _deleted.contains(task.parentId)) {
      _replace(task.copyWith(clearParent: true));
    }
    return _counted(_find(id));
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

  /// What deleting a section does to its tasks.
  void removeSection(String sectionId, {required bool deleteTasks}) {
    for (final t in List.of(_tasks)) {
      if (t.sectionId != sectionId) continue;
      if (deleteTasks) _deleted.add(t.id);
      _replace(t.copyWith(clearSection: true));
    }
  }
}
