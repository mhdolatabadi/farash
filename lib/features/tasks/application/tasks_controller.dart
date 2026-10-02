import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

/// The tasks of one project. Changes show at once and roll back when the API
/// refuses them.
class TasksController extends ChangeNotifier {
  TasksController({
    required TasksApi api,
    SectionsApi? sectionsApi,
    required this.token,
    required this.projectId,
  }) : _api = api,
       _sectionsApi = sectionsApi;

  final TasksApi _api;

  /// Null where sections are not available; the project then has none.
  final SectionsApi? _sectionsApi;
  final String? Function() token;
  final String projectId;

  List<Task> _tasks = const [];
  List<Section> _sections = const [];
  bool _loading = false;
  bool _showCompleted = false;
  Object? _error;
  bool _disposed = false;
  int _loadGeneration = 0;

  /// Tasks whose subtasks are folded away in the list.
  final _foldedTasks = <String>{};

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

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

  /// The project's sections in order.
  List<Section> get sections =>
      [..._sections]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  Section? sectionById(String? id) =>
      id == null ? null : _sections.where((s) => s.id == id).firstOrNull;

  /// The section a task shows under; a task whose section is gone shows
  /// without one.
  String? sectionOf(Task task) => sectionById(task.sectionId)?.id;

  Task? taskById(String? id) =>
      id == null ? null : _tasks.where((t) => t.id == id).firstOrNull;

  /// The open parent a task shows under; null for a top-level task, or when
  /// the parent is not in this list.
  Task? openParentOf(Task task) {
    final parent = taskById(task.parentId);
    return parent == null || parent.isCompleted ? null : parent;
  }

  /// Open top-level tasks of one section (null: tasks without a section), in
  /// order. Subtasks show under their parent; see [openChildren].
  List<Task> openIn(String? sectionId) => [
    for (final t in openTasks)
      if (openParentOf(t) == null && sectionOf(t) == sectionId) t,
  ];

  /// Open subtasks of [task], in order.
  List<Task> openChildren(Task task) => [
    for (final t in openTasks)
      if (t.parentId == task.id) t,
  ];

  /// Open tasks of a section as (task, depth) rows: each top-level task, then
  /// its subtasks one level deeper unless it is folded.
  List<(Task, int)> openTree(String? sectionId) {
    final rows = <(Task, int)>[];
    void visit(Task task, int depth) {
      rows.add((task, depth));
      if (isFolded(task)) return;
      for (final child in openChildren(task)) {
        visit(child, depth + 1);
      }
    }

    for (final task in openIn(sectionId)) {
      visit(task, 0);
    }
    return rows;
  }

  bool isFolded(Task task) => _foldedTasks.contains(task.id);

  /// Shows or hides a task's subtasks in the list.
  void setFolded(Task task, bool folded) {
    if (folded ? _foldedTasks.add(task.id) : _foldedTasks.remove(task.id)) {
      _publish();
    }
  }

  /// Every loaded task below [task].
  List<Task> descendantsOf(Task task) {
    final found = <Task>[];
    var level = [task.id];
    // Bounded like the API's five levels, so damaged data cannot loop.
    for (var depth = 0; depth < 16 && level.isNotEmpty; depth++) {
      final next = [
        for (final t in _tasks)
          if (level.contains(t.parentId)) t,
      ];
      found.addAll(next);
      level = [for (final t in next) t.id];
    }
    return found;
  }

  List<Task> _ancestorsOf(Task task) {
    final found = <Task>[];
    var parent = taskById(task.parentId);
    while (parent != null && found.length < 16) {
      found.add(parent);
      parent = taskById(parent.parentId);
    }
    return found;
  }

  bool _inTree(Task task) =>
      task.parentId != null ||
      task.hasSubtasks ||
      _tasks.any((t) => t.parentId == task.id);

  bool get isLoading => _loading;
  bool get showCompleted => _showCompleted;

  /// The last load failure, shown with a retry action.
  Object? get error => _error;

  Future<void> load() async {
    final requestToken = token();
    if (_disposed || requestToken == null) return;
    final generation = ++_loadGeneration;
    bool isCurrent() =>
        !_disposed && generation == _loadGeneration && token() == requestToken;
    _loading = true;
    _error = null;
    _publish();
    try {
      final sections = _sectionsApi?.listSections(requestToken, projectId);
      final loaded = await _api.listTasks(
        requestToken,
        projectId,
        showCompleted: _showCompleted,
      );
      final loadedSections = sections == null
          ? const <Section>[]
          : await sections;
      if (isCurrent()) {
        _tasks = loaded;
        _sections = loadedSections;
      }
    } catch (error) {
      if (isCurrent()) _error = error;
    } finally {
      if (isCurrent()) {
        _loading = false;
        _publish();
      }
    }
  }

  /// Reloads the tasks without the loading state, after a change whose
  /// effects reach other tasks (subtasks closing with their parent, progress
  /// counts). A failure keeps what is shown.
  Future<void> _refresh() async {
    final requestToken = token();
    if (_disposed || requestToken == null) return;
    final generation = ++_loadGeneration;
    try {
      final loaded = await _api.listTasks(
        requestToken,
        projectId,
        showCompleted: _showCompleted,
      );
      if (!_disposed &&
          generation == _loadGeneration &&
          token() == requestToken) {
        _tasks = loaded;
        _loading = false;
        _error = null;
        _publish();
      }
    } catch (_) {
      // The optimistic state stays; the next load corrects it.
    }
  }

  Future<void> setShowCompleted(bool show) async {
    if (show == _showCompleted) return;
    _showCompleted = show;
    await load();
  }

  /// Adds a task at the end of the open list, or of [parent]'s subtasks.
  Future<Task> add(
    String title, {
    TaskPriority priority = TaskPriority.p4,
    String? sectionId,
    Task? parent,
  }) async {
    final siblings = parent == null ? openTasks : openChildren(parent);
    final task = await _api.createTask(
      _requireToken(),
      TaskDraft(
        // A subtask takes its parent's project and section.
        projectId: parent == null ? projectId : null,
        sectionId: parent == null ? sectionId : null,
        parentId: parent?.id,
        title: title.trim(),
        priority: priority,
        sortOrder: siblings.isEmpty
            ? 0
            : siblings.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) +
                  1,
      ),
    );
    _tasks = [
      for (final t in _tasks)
        if (t.id == parent?.id)
          t.copyWith(subtaskCount: t.subtaskCount + 1)
        else
          t,
      task,
    ];
    if (parent != null) _foldedTasks.remove(parent.id);
    _publish();
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
    String? sectionId,
    TaskDates? dates,
  }) async {
    final moved = projectId != this.projectId;
    final sectionChanged = !moved && sectionId != sectionOf(task);
    final updated = await _api.updateTask(
      _requireToken(),
      task.id,
      TaskDraft(
        title: title.trim(),
        description: description,
        priority: priority,
        projectId: moved ? projectId : null,
        // The API takes the task out of its section when it changes project.
        sectionId: sectionChanged ? (sectionId ?? '') : null,
        dates: dates == null || dates == task.dates ? null : dates,
      ),
    );
    _tasks = [
      for (final t in _tasks)
        if (t.id != task.id) t else if (!moved) updated,
    ];
    _publish();
    // Subtasks follow their parent to its new place.
    if (_inTree(task)) await _refresh();
  }

  /// Gives [tasks] the same [due] (null: no date) at once, keeping their
  /// other fields. Shows at once and rolls back if the API refuses it.
  Future<void> reschedule(List<Task> tasks, TaskDue? due) async {
    if (tasks.isEmpty) return;
    final before = _tasks;
    final ids = {for (final t in tasks) t.id};
    _tasks = [
      for (final t in _tasks)
        if (ids.contains(t.id))
          t.copyWith(
            dates: TaskDates(
              due: due,
              deadline: t.deadline,
              durationMinutes: t.durationMinutes,
            ),
          )
        else
          t,
    ];
    _publish();
    try {
      final saved = await _api.rescheduleTasks(_requireToken(), [
        for (final t in tasks) t.id,
      ], due);
      final byId = {for (final t in saved) t.id: t};
      _tasks = [for (final t in _tasks) byId[t.id] ?? t];
      _publish();
    } catch (_) {
      _tasks = before;
      _publish();
      rethrow;
    }
  }

  /// Saves a new description on its own, as ticking a checklist item does.
  Future<void> saveDescription(Task task, String description) async {
    final saved = await _api.updateTask(
      _requireToken(),
      task.id,
      TaskDraft(description: description),
    );
    _tasks = [
      for (final t in _tasks)
        if (t.id == saved.id) saved else t,
    ];
    _publish();
  }

  /// Checks a task off, or back on. Calling it again with the opposite value
  /// is the undo.
  Future<void> setCompleted(Task task, bool completed) async {
    final before = _tasks;
    final now = DateTime.now();
    final tree = _inTree(task);
    // Closing a task closes its open subtasks; reopening a subtask reopens
    // its parents. The API does the same, and the refresh below confirms it.
    final cascade = {
      for (final t in completed ? descendantsOf(task) : _ancestorsOf(task))
        if (t.isCompleted != completed) t.id,
    };
    final changes = task.isCompleted != completed;
    _tasks = [
      for (final t in _tasks)
        if (t.id != task.id && !cascade.contains(t.id))
          t.id == task.parentId && changes
              ? t.copyWith(
                  completedSubtaskCount:
                      t.completedSubtaskCount + (completed ? 1 : -1),
                )
              : t
        else
          completed
              ? t.copyWith(completedAt: now)
              : t.copyWith(clearCompletedAt: true),
    ];
    // An undo of a hidden completion puts the task back in the list.
    if (!completed && !_tasks.any((t) => t.id == task.id)) {
      _tasks = [..._tasks, task.copyWith(clearCompletedAt: true)];
    }
    _publish();
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
            if (t.id != saved.id && !cascade.contains(t.id)) t,
        ];
      }
      _publish();
      if (tree || saved.hasSubtasks || saved.parentId != null) {
        await _refresh();
      }
    } catch (_) {
      _tasks = before;
      _publish();
      rethrow;
    }
  }

  /// Removes a task with its subtasks; [undoDelete] restores them.
  Future<void> delete(Task task) async {
    final before = _tasks;
    final gone = {task.id, for (final t in descendantsOf(task)) t.id};
    _tasks = [
      for (final t in _tasks)
        if (t.id == task.parentId)
          t.copyWith(
            subtaskCount: t.subtaskCount - 1,
            completedSubtaskCount:
                t.completedSubtaskCount - (task.isCompleted ? 1 : 0),
          )
        else if (!gone.contains(t.id))
          t,
    ];
    _publish();
    try {
      await _api.deleteTask(_requireToken(), task.id);
    } catch (_) {
      _tasks = before;
      _publish();
      rethrow;
    }
  }

  Future<void> undoDelete(Task task) async {
    final restored = await _api.restoreTask(_requireToken(), task.id);
    if (restored.parentId != null || restored.hasSubtasks) {
      await _refresh();
      return;
    }
    if (restored.projectId == projectId &&
        (!restored.isCompleted || _showCompleted)) {
      _tasks = [..._tasks, restored];
      _publish();
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
    _publish();
    try {
      await _api.reorderTasks(_requireToken(), projectId, [
        for (final t in open) t.id,
      ]);
    } catch (_) {
      _tasks = before;
      _publish();
      rethrow;
    }
  }

  /// Puts [task] into [sectionId] (null: no section) under [parent] (null:
  /// top-level), with [orderedIds] its new open siblings in order. Its
  /// subtasks go with it.
  Future<void> moveTask(
    Task task,
    String? sectionId,
    List<String> orderedIds, {
    Task? parent,
  }) async {
    if (parent != null &&
        (parent.id == task.id ||
            descendantsOf(task).any((t) => t.id == parent.id))) {
      return;
    }
    final before = _tasks;
    final order = {
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    final targetSection = parent == null ? sectionId : parent.sectionId;
    final parentChanged = task.parentId != parent?.id;
    final sectionChanged = sectionOf(task) != targetSection;
    final moving = {task.id, for (final t in descendantsOf(task)) t.id};
    _tasks = [
      for (final t in _tasks)
        if (t.id == task.id)
          t.copyWith(
            sectionId: targetSection,
            clearSection: targetSection == null,
            parentId: parent?.id,
            clearParent: parent == null,
            sortOrder: order[t.id],
          )
        else if (moving.contains(t.id))
          t.copyWith(
            sectionId: targetSection,
            clearSection: targetSection == null,
          )
        else if (order.containsKey(t.id))
          t.copyWith(sortOrder: order[t.id])
        else
          t,
    ];
    if (parent != null) _foldedTasks.remove(parent.id);
    _publish();
    try {
      final token = _requireToken();
      if (parentChanged) {
        await _api.updateTask(
          token,
          task.id,
          parent != null
              ? TaskDraft(parentId: parent.id)
              : TaskDraft(
                  parentId: '',
                  sectionId: sectionChanged ? (sectionId ?? '') : null,
                ),
        );
      } else if (sectionChanged) {
        await _api.updateTask(
          token,
          task.id,
          TaskDraft(sectionId: sectionId ?? ''),
        );
      }
      await _api.reorderTasks(token, projectId, orderedIds);
    } catch (_) {
      _tasks = before;
      _publish();
      rethrow;
    }
    if (parentChanged) await _refresh();
  }

  /// The open task right above [task] at its level, which it can nest
  /// under; null when it is the first.
  Task? indentTarget(Task task) {
    final parent = openParentOf(task);
    final siblings = parent == null
        ? openIn(sectionOf(task))
        : openChildren(parent);
    final index = siblings.indexWhere((t) => t.id == task.id);
    return index > 0 ? siblings[index - 1] : null;
  }

  /// Nests [task] as the last subtask of the task above it.
  Future<void> indent(Task task) async {
    final target = indentTarget(task);
    if (target == null) return;
    await moveTask(task, sectionOf(task), [
      for (final t in openChildren(target)) t.id,
      task.id,
    ], parent: target);
  }

  /// Moves [task] one level up, right after its current parent.
  Future<void> outdent(Task task) async {
    final parent = openParentOf(task);
    if (parent == null) return;
    final grandparent = openParentOf(parent);
    final siblings = grandparent == null
        ? openIn(sectionOf(parent))
        : openChildren(grandparent);
    final ids = [
      for (final t in siblings)
        if (t.id != task.id) t.id,
    ];
    ids.insert(ids.indexOf(parent.id) + 1, task.id);
    await moveTask(task, sectionOf(parent), ids, parent: grandparent);
  }

  Future<Section> addSection(String name) async {
    final section = await _requireSections().createSection(
      _requireToken(),
      projectId,
      name.trim(),
    );
    _sections = [..._sections, section];
    _publish();
    return section;
  }

  Future<void> renameSection(Section section, String name) async {
    final saved = await _requireSections().updateSection(
      _requireToken(),
      section.id,
      name: name.trim(),
    );
    _replaceSection(saved);
  }

  /// Collapsing shows at once and rolls back if the API refuses it.
  Future<void> setCollapsed(Section section, bool collapsed) async {
    final before = _sections;
    _replaceSection(section.copyWith(isCollapsed: collapsed));
    try {
      await _requireSections().updateSection(
        _requireToken(),
        section.id,
        isCollapsed: collapsed,
      );
    } catch (_) {
      _sections = before;
      _publish();
      rethrow;
    }
  }

  /// Deletes a section. Its tasks stay in the project without a section,
  /// or are deleted too with [deleteTasks].
  Future<void> deleteSection(
    Section section, {
    required bool deleteTasks,
  }) async {
    await _requireSections().deleteSection(
      _requireToken(),
      section.id,
      deleteTasks: deleteTasks,
    );
    _sections = [
      for (final s in _sections)
        if (s.id != section.id) s,
    ];
    _tasks = [
      for (final t in _tasks)
        if (t.sectionId != section.id)
          t
        else if (!deleteTasks)
          t.copyWith(clearSection: true),
    ];
    _publish();
  }

  /// Moves [section] to [newIndex] among the sections.
  Future<void> moveSection(Section section, int newIndex) async {
    final ordered = sections;
    final oldIndex = ordered.indexWhere((s) => s.id == section.id);
    if (oldIndex < 0 || oldIndex == newIndex) return;
    ordered.removeAt(oldIndex);
    ordered.insert(newIndex.clamp(0, ordered.length), section);
    final before = _sections;
    _sections = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i),
    ];
    _publish();
    try {
      await _requireSections().reorderSections(_requireToken(), projectId, [
        for (final s in ordered) s.id,
      ]);
    } catch (_) {
      _sections = before;
      _publish();
      rethrow;
    }
  }

  void _replaceSection(Section updated) {
    _sections = [
      for (final s in _sections)
        if (s.id == updated.id) updated else s,
    ];
    _publish();
  }

  SectionsApi _requireSections() {
    final api = _sectionsApi;
    if (api == null) throw StateError('Sections are not available.');
    return api;
  }

  String _requireToken() {
    final token = this.token();
    if (token == null) {
      throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.');
    }
    return token;
  }
}
