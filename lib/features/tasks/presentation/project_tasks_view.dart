import 'package:flutter/material.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:farash/features/tasks/presentation/section_dialogs.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

/// Readable width for the task list on wide screens.
const _maxListWidth = 760.0;

/// A project's tasks, grouped by section, with quick add at the bottom.
class ProjectTasksView extends StatefulWidget {
  const ProjectTasksView({
    super.key,
    required this.project,
    required this.api,
    required this.token,
    required this.moveTargets,
    this.sectionsApi,
  });

  final Project project;
  final TasksApi api;

  /// Null where sections are not available.
  final SectionsApi? sectionsApi;
  final String? Function() token;

  /// The projects a task may move to.
  final List<Project> Function() moveTargets;

  @override
  State<ProjectTasksView> createState() => _ProjectTasksViewState();
}

/// One row of the open list: a task, or the header of a section.
sealed class _Row {
  const _Row();
}

class _TaskRow extends _Row {
  const _TaskRow(this.task, this.depth);
  final Task task;

  /// 0 for a top-level task, 1 for its subtasks, and so on.
  final int depth;
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.section);
  final Section section;
}

class _ProjectTasksViewState extends State<ProjectTasksView> {
  late final TasksController _tasks = TasksController(
    api: widget.api,
    sectionsApi: widget.sectionsApi,
    token: widget.token,
    projectId: widget.project.id,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.project.isFolder) _tasks.load();
  }

  @override
  void dispose() {
    _tasks.dispose();
    super.dispose();
  }

  void _snack(String message, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: undo == null
            ? null
            : SnackBarAction(label: 'برگرداندن', onPressed: undo),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showTaskError(context, error);
    }
  }

  Future<void> _toggle(Task task) => _run(() async {
    final completing = !task.isCompleted;
    await _tasks.setCompleted(task, completing);
    if (completing && mounted) {
      _snack(
        '«${task.title}» انجام شد.',
        undo: () => _run(() => _tasks.setCompleted(task, false)),
      );
    }
  });

  Future<void> _delete(Task task) => _run(() async {
    await _tasks.delete(task);
    if (mounted) {
      _snack(
        '«${task.title}» حذف شد.',
        undo: () => _run(() => _tasks.undoDelete(task)),
      );
    }
  });

  Task? _editingTask;
  var _editorKey = GlobalKey();

  /// Tasks picked for a bulk change; a long press starts picking.
  final _selected = <String>{};

  List<Task> get _selectedTasks => [
    for (final t in _tasks.tasks)
      if (_selected.contains(t.id)) t,
  ];

  void _toggleSelected(Task task) => setState(() {
    if (!_selected.remove(task.id)) _selected.add(task.id);
  });

  Future<void> _rescheduleSelected() async {
    final tasks = _selectedTasks;
    if (tasks.isEmpty) return;
    final dues = {for (final t in tasks) t.due};
    final picked = await showDuePicker(
      context,
      dueOnly: true,
      initial: TaskDates(due: dues.length == 1 ? dues.single : null),
    );
    if (picked == null || !mounted) return;
    await _run(() async {
      await _tasks.reschedule(tasks, picked.due);
      if (!mounted) return;
      setState(_selected.clear);
      _snack('تاریخ ${persianDigits(tasks.length)} کار تغییر کرد.');
    });
  }

  Future<void> _editorResult(TaskSheetResult? result) async {
    final task = _editingTask;
    setState(() => _editingTask = null);
    if (result == TaskSheetResult.deleted && task != null) await _delete(task);
  }

  Future<void> _open(Task task) async {
    if ((context.size?.width ?? 0) >= 820) {
      setState(() {
        _editorKey = GlobalKey();
        _editingTask = task;
      });
      return;
    }
    final result = await showTaskDetailSheet(
      context,
      controller: _tasks,
      task: task,
      projects: widget.moveTargets(),
    );
    if (result == TaskSheetResult.deleted) await _delete(task);
  }

  /// The open list: tasks without a section, then each section's header and
  /// (unless it is collapsed) its tasks, each followed by its subtasks.
  List<_Row> _rows() => [
    for (final (task, depth) in _tasks.openTree(null)) _TaskRow(task, depth),
    for (final section in _tasks.sections) ...[
      _HeaderRow(section),
      if (!section.isCollapsed)
        for (final (task, depth) in _tasks.openTree(section.id))
          _TaskRow(task, depth),
    ],
  ];

  /// A dropped task joins the section whose header is above it, at the level
  /// of the task above it: as its sibling, or as the first subtask when the
  /// row below is already one of that task's subtasks.
  void _onReorder(List<_Row> rows, int from, int to) {
    final moved = rows[from];
    if (moved is! _TaskRow) return;
    final next = [...rows]..removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    final at = next.indexOf(moved);
    final above = at > 0 ? next[at - 1] : null;
    final below = at + 1 < next.length ? next[at + 1] : null;
    Task? parent;
    if (above is _TaskRow) {
      parent = below is _TaskRow && below.depth > above.depth
          ? above.task
          : _tasks.openParentOf(above.task);
    }

    Section? section;
    for (var i = at; i >= 0; i--) {
      final row = next[i];
      if (row is _HeaderRow) {
        section = row.section;
        break;
      }
    }
    // The new siblings between that header (or the top) and the next
    // header, in their new order.
    final first = section == null
        ? 0
        : next.indexWhere(
                (r) => r is _HeaderRow && r.section.id == section!.id,
              ) +
              1;
    final ids = <String>[];
    for (var i = first; i < next.length; i++) {
      final row = next[i];
      if (row is _HeaderRow) break;
      if (row is _TaskRow &&
          (row == moved || _tasks.openParentOf(row.task)?.id == parent?.id)) {
        ids.add(row.task.id);
      }
    }
    // A collapsed section's tasks are not on screen; keep them after it.
    if (parent == null && section != null && section.isCollapsed) {
      for (final t in _tasks.openIn(section.id)) {
        if (!ids.contains(t.id)) ids.add(t.id);
      }
    }
    _run(() => _tasks.moveTask(moved.task, section?.id, ids, parent: parent));
  }

  Future<void> _addSection() async {
    final name = await askSectionName(context, title: 'بخش تازه');
    if (name != null) await _run(() => _tasks.addSection(name));
  }

  Future<void> _addTaskTo(Section section) async {
    final title = await askTaskTitle(context, section.name);
    if (title != null) {
      await _run(() => _tasks.add(title, sectionId: section.id));
    }
  }

  Future<void> _sectionAction(Section section, SectionAction action) async {
    final ordered = _tasks.sections;
    final index = ordered.indexWhere((s) => s.id == section.id);
    switch (action) {
      case SectionAction.rename:
        final name = await askSectionName(
          context,
          title: 'تغییر نام بخش',
          initial: section.name,
        );
        if (name != null) {
          await _run(() => _tasks.renameSection(section, name));
        }
      case SectionAction.moveUp:
        await _run(() => _tasks.moveSection(section, index - 1));
      case SectionAction.moveDown:
        await _run(() => _tasks.moveSection(section, index + 1));
      case SectionAction.delete:
        final choice = await confirmSectionDelete(
          context,
          section,
          taskCount: _tasks.openIn(section.id).length,
        );
        if (choice != null) {
          await _run(
            () => _tasks.deleteSection(
              section,
              deleteTasks: choice == SectionDeleteChoice.withTasks,
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.isFolder) return const _FolderNotice();
    final list = Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: _tasks,
            builder: (context, _) => _list(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _QuickAdd(
            projectName: widget.project.displayName,
            onAdd: (title, priority) async {
              try {
                await _tasks.add(title, priority: priority);
                return true;
              } catch (error) {
                if (mounted) showTaskError(this.context, error);
                return false;
              }
            },
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final task = _editingTask;
        if (task == null) return list;
        final editor = TaskDetailEditor(
          key: _editorKey,
          controller: _tasks,
          task: task,
          projects: widget.moveTargets(),
          onResult: _editorResult,
        );
        return Row(
          children: [
            if (constraints.maxWidth >= 820) ...[
              Expanded(child: list),
              const SizedBox(width: 12),
              SizedBox(width: 380, child: editor),
            ] else
              Expanded(child: editor),
          ],
        );
      },
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    if (_tasks.isLoading && _tasks.tasks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tasks.error != null && _tasks.tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(taskErrorMessage(_tasks.error!)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _tasks.load,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      );
    }
    final rows = _rows();
    final done = _tasks.completedTasks;
    final sectionsAvailable = widget.sectionsApi != null;
    final sections = _tasks.sections;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxListWidth),
        child: RefreshIndicator(
          onRefresh: _tasks.load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _selectedTasks.isNotEmpty
                      ? _SelectionBar(
                          count: _selectedTasks.length,
                          onReschedule: _rescheduleSelected,
                          onCancel: () => setState(_selected.clear),
                        )
                      : Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilterChip(
                            label: const Text('نمایش انجام‌شده‌ها'),
                            selected: _tasks.showCompleted,
                            onSelected: (show) =>
                                _run(() => _tasks.setShowCompleted(show)),
                          ),
                        ),
                ),
              ),
              if (rows.isEmpty && done.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Text(
                      'هنوز کاری در «${widget.project.displayName}» نیست.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              SliverReorderableList(
                itemCount: rows.length,
                onReorderItem: (from, to) => _onReorder(rows, from, to),
                itemBuilder: (context, index) => switch (rows[index]) {
                  _TaskRow(:final task, :final depth) => Material(
                    key: ValueKey(task.id),
                    color: _selected.contains(task.id)
                        ? theme.colorScheme.secondaryContainer
                        : Colors.transparent,
                    child: TaskTile(
                      selected: _selected.contains(task.id),
                      onLongPress: () => _toggleSelected(task),
                      task: task,
                      depth: depth,
                      folded: _tasks.openChildren(task).isEmpty
                          ? null
                          : _tasks.isFolded(task),
                      onFold: () =>
                          _tasks.setFolded(task, !_tasks.isFolded(task)),
                      onToggle: () => _toggle(task),
                      onOpen: () => _selectedTasks.isNotEmpty
                          ? _toggleSelected(task)
                          : _open(task),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Tooltip(
                          message: 'جابه‌جا کردن',
                          child: SizedBox.square(
                            dimension: 48,
                            child: Icon(
                              Icons.drag_indicator,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _HeaderRow(:final section) => SectionHeader(
                    key: ValueKey('section-${section.id}'),
                    section: section,
                    taskCount: _tasks.openIn(section.id).length,
                    isFirst: section.id == sections.first.id,
                    isLast: section.id == sections.last.id,
                    onToggle: () => _run(
                      () => _tasks.setCollapsed(section, !section.isCollapsed),
                    ),
                    onAddTask: () => _addTaskTo(section),
                    onAction: (action) => _sectionAction(section, action),
                  ),
                },
              ),
              if (sectionsAvailable)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _addSection,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('افزودن بخش'),
                      ),
                    ),
                  ),
                ),
              if (done.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      16,
                      16,
                      4,
                    ),
                    child: Text(
                      'انجام‌شده',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                SliverList.list(
                  children: [
                    for (final task in done)
                      TaskTile(
                        key: ValueKey('done-${task.id}'),
                        task: task,
                        onToggle: () => _toggle(task),
                        onOpen: () => _open(task),
                      ),
                  ],
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the filter while tasks are picked.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onReschedule,
    required this.onCancel,
  });

  final int count;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'لغو انتخاب',
          onPressed: onCancel,
          icon: const Icon(Icons.close),
        ),
        Expanded(
          child: Text(
            '${persianDigits(count)} کار انتخاب شد',
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: onReschedule,
          icon: const Icon(Icons.event),
          label: const Text('تغییر تاریخ'),
        ),
      ],
    );
  }
}

/// One field and one button, pinned under the list and above the keyboard.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({required this.projectName, required this.onAdd});

  final String projectName;

  /// Returns whether the task was added, so the field keeps its text on
  /// failure.
  final Future<bool> Function(String title, TaskPriority priority) onAdd;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  TaskPriority _priority = TaskPriority.p4;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _text.text.trim();
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    final added = await widget.onAdd(title, _priority);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (added) {
        _text.clear();
        _priority = TaskPriority.p4;
      }
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 16,
      blur: 10,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxListWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Row(
                children: [
                  PopupMenuButton<TaskPriority>(
                    tooltip: 'اولویت: ${_priority.label}',
                    initialValue: _priority,
                    icon: Icon(Icons.flag, color: _priority.color),
                    onSelected: (p) => setState(() => _priority = p),
                    itemBuilder: (context) => [
                      for (final p in TaskPriority.values)
                        PopupMenuItem(
                          value: p,
                          child: Row(
                            children: [
                              Icon(Icons.flag, color: p.color),
                              const SizedBox(width: 8),
                              Text(p.label),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      textInputAction: TextInputAction.send,
                      maxLength: 500,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => null,
                      decoration: InputDecoration(
                        hintText: 'کار تازه در «${widget.projectName}»',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: 'افزودن کار',
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderNotice extends StatelessWidget {
  const _FolderNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'پوشه فقط پروژه نگه می‌دارد. یکی از پروژه‌های داخلش را باز کنید.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
