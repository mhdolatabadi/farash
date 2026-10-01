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

  /// Open tasks of one section (null: tasks without a section), in order.
  List<Task> openIn(String? sectionId) => [
    for (final t in openTasks)
      if (sectionOf(t) == sectionId) t,
  ];

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
      final sections = _sectionsApi?.listSections(token, projectId);
      _tasks = await _api.listTasks(
        token,
        projectId,
        showCompleted: _showCompleted,
      );
      _sections = sections == null ? const [] : await sections;
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
    String? sectionId,
  }) async {
    final open = openTasks;
    final task = await _api.createTask(
      _requireToken(),
      TaskDraft(
        projectId: projectId,
        sectionId: sectionId,
        title: title.trim(),
        priority: priority,
        sortOrder: open.isEmpty
            ? 0
            : open.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
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
    String? sectionId,
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

  /// Puts [task] into [sectionId] (null: no section), with [orderedIds] the
  /// open tasks of that section in their new order.
  Future<void> moveTask(
    Task task,
    String? sectionId,
    List<String> orderedIds,
  ) async {
    final before = _tasks;
    final order = {
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    final sectionChanged = sectionOf(task) != sectionId;
    _tasks = [
      for (final t in _tasks)
        if (t.id == task.id)
          t.copyWith(
            sectionId: sectionId,
            clearSection: sectionId == null,
            sortOrder: order[t.id],
          )
        else if (order.containsKey(t.id))
          t.copyWith(sortOrder: order[t.id])
        else
          t,
    ];
    notifyListeners();
    try {
      final token = _requireToken();
      if (sectionChanged) {
        await _api.updateTask(
          token,
          task.id,
          TaskDraft(sectionId: sectionId ?? ''),
        );
      }
      await _api.reorderTasks(token, projectId, orderedIds);
    } catch (_) {
      _tasks = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<Section> addSection(String name) async {
    final section = await _requireSections().createSection(
      _requireToken(),
      projectId,
      name.trim(),
    );
    _sections = [..._sections, section];
    notifyListeners();
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
      notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    try {
      await _requireSections().reorderSections(_requireToken(), projectId, [
        for (final s in ordered) s.id,
      ]);
    } catch (_) {
      _sections = before;
      notifyListeners();
      rethrow;
    }
  }

  void _replaceSection(Section updated) {
    _sections = [
      for (final s in _sections)
        if (s.id == updated.id) updated else s,
    ];
    notifyListeners();
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
