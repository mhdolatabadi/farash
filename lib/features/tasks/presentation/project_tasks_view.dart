import 'dart:async';

import 'package:flutter/material.dart';
import 'package:farash/app/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:farash/app/list_app_bar.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/core/widgets/hover_reveal.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:farash/features/tasks/presentation/priority_color.dart';
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
    this.showTitle = false,
    this.labels,
  });

  final Project project;
  final TasksApi api;

  /// Null where sections are not available.
  final SectionsApi? sectionsApi;
  final String? Function() token;

  /// The projects a task may move to.
  final List<Project> Function() moveTargets;

  /// Shows the project name as the list's heading, where no app bar does.
  final bool showTitle;

  /// The account's labels, for the editor and the rows' tags.
  final LabelsController? labels;

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

  /// Rows folding away after a check, with what waits on them.
  final _leaving = <String, Completer<void>>{};

  /// Rows just added, which grow in.
  final _entering = <String>{};

  Future<void> _toggle(Task task) => _run(() async {
    final completing = !task.isCompleted;
    if (completing &&
        !Motion.reduced(context) &&
        !_leaving.containsKey(task.id)) {
      final exited = Completer<void>();
      setState(() => _leaving[task.id] = exited);
      await exited.future;
    }
    try {
      await _tasks.setCompleted(task, completing);
    } finally {
      if (mounted && _leaving.remove(task.id) != null) setState(() {});
    }
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
  final _captureKey = GlobalKey();

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
      labels: widget.labels,
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

  /// Adds the task quick-add text describes: its dates, priority and
  /// labels, in the project after `#` when that names another one.
  Future<void> _addParsed(
    QuickTask parsed,
    String raw,
    TaskPriority menuPriority,
  ) async {
    final priority = parsed.priority == null
        ? menuPriority
        : TaskPriority.fromLevel(parsed.priority!);
    TaskDue? due;
    if (parsed.day case final day?) {
      due = parsed.hour == null
          ? TaskDue.onDay(day)
          : TaskDue.at(
              DateTime(
                day.year,
                day.month,
                day.day,
                parsed.hour!,
                parsed.minute,
              ),
              await deviceTimeZone(),
            );
    }
    final dates = due == null && parsed.deadline == null
        ? null
        : TaskDates(
            due: due,
            deadline: parsed.deadline == null
                ? null
                : dateKey(parsed.deadline!),
          );
    final labelIds = await _labelIdsFor(parsed.labels);
    var title = parsed.title;
    Project? target;
    if (parsed.project case final name?) {
      target = widget
          .moveTargets()
          .where(
            (p) =>
                !p.isFolder &&
                p.displayName.toLowerCase() == name.toLowerCase(),
          )
          .firstOrNull;
      // An unknown project stays as text rather than vanishing.
      if (target == null) title = '$title #$name'.trim();
    }
    if (title.isEmpty) title = raw.trim();
    if (target != null && target.id != widget.project.id) {
      final token = widget.token();
      if (token == null) return;
      await widget.api.createTask(
        token,
        TaskDraft(
          projectId: target.id,
          title: title,
          priority: priority,
          dates: dates,
          labelIds: labelIds,
        ),
      );
      _snack('«$title» به «${target.displayName}» اضافه شد.');
      return;
    }
    final task = await _tasks.add(
      title,
      priority: priority,
      dates: dates,
      labelIds: labelIds,
    );
    if (mounted) setState(() => _entering.add(task.id));
  }

  /// The ids of labels named in quick add, making the ones that do not
  /// exist yet.
  Future<List<String>?> _labelIdsFor(List<String> names) async {
    final labels = widget.labels;
    if (names.isEmpty || labels == null) return null;
    final ids = <String>[];
    for (final name in names) {
      final existing = labels.labels
          .where((l) => l.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      ids.add(existing?.id ?? (await labels.create(LabelDraft(name: name))).id);
    }
    return ids;
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

  /// The capture bar's height, so the list can scroll clear of it.
  double _dockHeight = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.project.isFolder) return const _FolderNotice();
    return LayoutBuilder(
      builder: (context, constraints) {
        // With a landscape keyboard, reserve no fixed footer: capture and
        // tasks share one scrollable viewport so neither can trap the other.
        final compact = constraints.maxHeight < 240;
        final capture = _QuickAdd(
          key: _captureKey,
          projectName: widget.project.displayName,
          onAdd: (parsed, raw, priority) async {
            try {
              await _addParsed(parsed, raw, priority);
              return true;
            } catch (error) {
              if (mounted) showTaskError(this.context, error);
              return false;
            }
          },
        );
        final wide = constraints.maxWidth >= 820;
        final task = _editingTask;
        final listWidth = task != null && wide
            ? constraints.maxWidth - _editorWidth - 12
            : constraints.maxWidth;
        final taskList = ListenableBuilder(
          listenable: _tasks,
          builder: (context, _) => _list(
            context,
            width: listWidth,
            compact: compact,
            capture: compact
                ? Padding(padding: const EdgeInsets.all(12), child: capture)
                : null,
          ),
        );
        // The capture bar floats over the end of the list, which scrolls
        // under it.
        final list = compact
            ? taskList
            : Stack(
                children: [
                  Positioned.fill(child: taskList),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: 0,
                    child: _MeasureSize(
                      onChange: (size) {
                        if (size.height != _dockHeight) {
                          setState(() => _dockHeight = size.height);
                        }
                      },
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _maxListWidth,
                              ),
                              child: capture,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
        if (task == null) return list;
        final editor = TaskDetailEditor(
          key: _editorKey,
          controller: _tasks,
          task: task,
          projects: widget.moveTargets(),
          labels: widget.labels,
          onResult: _editorResult,
        );
        if (!wide) return editor;
        // A standard side sheet: full height at the end edge, beside the
        // list rather than over it.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 12, 12),
              child: SizedBox(width: _editorWidth, child: editor),
            ),
          ],
        );
      },
    );
  }

  Widget _list(
    BuildContext context, {
    required double width,
    required bool compact,
    Widget? capture,
  }) {
    final theme = Theme.of(context);
    Widget? status;
    if (_tasks.isLoading && _tasks.tasks.isEmpty) {
      status = const Center(child: CircularProgressIndicator());
    } else if (_tasks.error != null && _tasks.tasks.isEmpty) {
      status = Center(
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
    final touch = HoverReveal.isTouch(context);
    Widget handle(int index) => HoverReveal(
      child: ReorderableDragStartListener(
        index: index,
        child: Tooltip(
          message: 'جابه‌جا کردن',
          child: SizedBox.square(
            dimension: 48,
            child: Icon(
              Icons.drag_indicator,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
    final sectionsAvailable = widget.sectionsApi != null;
    final sections = _tasks.sections;
    // Content keeps a readable width; the app bar spans the whole
    // column so the list can pass under it.
    final inset = width > _maxListWidth ? (width - _maxListWidth) / 2 : 0.0;
    Widget pad(Widget sliver) => SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      sliver: sliver,
    );
    final openCount = _tasks.openTasks.length;
    final plannedMinutes = _tasks.openTasks.fold<int>(
      0,
      (sum, t) => sum + (t.durationMinutes ?? 0),
    );
    final countText = openCount == 0
        ? 'کار بازی نمانده'
        : plannedMinutes == 0
        ? '${persianDigits(openCount)} کار باز'
        : '${persianDigits(openCount)} کار باز · ${formatDuration(plannedMinutes)}';
    final completedToggle = IconButton(
      tooltip: _tasks.showCompleted
          ? 'پنهان کردن انجام‌شده‌ها'
          : 'نمایش انجام‌شده‌ها',
      isSelected: _tasks.showCompleted,
      icon: const Icon(Icons.visibility_outlined),
      selectedIcon: const Icon(Icons.visibility),
      onPressed: () =>
          _run(() => _tasks.setShowCompleted(!_tasks.showCompleted)),
    );
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final topPadding = MediaQuery.paddingOf(context).top;
    final selecting = _selectedTasks.isNotEmpty;
    final selectionBar = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: _SelectionBar(
        count: _selectedTasks.length,
        onReschedule: _rescheduleSelected,
        onCancel: () => setState(_selected.clear),
      ),
    );
    return RefreshIndicator(
      onRefresh: _tasks.load,
      edgeOffset: widget.showTitle ? topPadding + listBarHeight : 0,
      child: CustomScrollView(
        slivers: [
          if (widget.showTitle)
            SliverPersistentHeader(
              pinned: !compact,
              delegate: ListAppBar(
                title: widget.project.displayName,
                subtitle: countText,
                mark: widget.project.isInbox
                    ? Icon(
                        Icons.inbox_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : Icon(
                        Icons.circle,
                        size: 12,
                        color: widget.project.swatch,
                      ),
                actions: [completedToggle],
                topPadding: topPadding,
                inset: inset,
                expandedHeight: compact ? 0 : 32 * scale,
              ),
            ),
          if (capture != null) pad(SliverToBoxAdapter(child: capture)),
          if (selecting)
            pad(SliverToBoxAdapter(child: selectionBar))
          else if (!widget.showTitle)
            pad(
              SliverToBoxAdapter(
                child: _ListHeader(count: countText, toggle: completedToggle),
              ),
            ),
          if (status != null)
            SliverFillRemaining(hasScrollBody: false, child: status)
          else ...[
            if (rows.isEmpty && done.isEmpty)
              pad(
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'هنوز کاری در «${widget.project.displayName}» نیست.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'کار تازه را در کادر افزودن بنویسید.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (rows.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: inset + 12),
                sliver: DecoratedSliver(
                  decoration: const BoxDecoration(),
                  sliver: SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    sliver: SliverReorderableList(
                      itemCount: rows.length,
                      onReorderItem: (from, to) => _onReorder(rows, from, to),
                      itemBuilder: (context, index) => switch (rows[index]) {
                        _TaskRow(:final task, :final depth) => RowMotion(
                          key: ValueKey(task.id),
                          entering: _entering.remove(task.id),
                          leaving: _leaving.containsKey(task.id),
                          onExited: () => _leaving[task.id]?.complete(),
                          child: Material(
                            color: _selected.contains(task.id)
                                ? theme.colorScheme.secondaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: HoverRegion(
                              child: TaskTile(
                                selected: _selected.contains(task.id),
                                onLongPress: () => _toggleSelected(task),
                                // A row folding away shows as checked meanwhile.
                                task: _leaving.containsKey(task.id)
                                    ? task.copyWith(completedAt: DateTime.now())
                                    : task,
                                stamped: _leaving.containsKey(task.id),
                                divider: index < rows.length - 1,
                                labels: [
                                  for (final id in task.labelIds)
                                    ?widget.labels?.byId(id),
                                ],
                                depth: depth,
                                folded: _tasks.openChildren(task).isEmpty
                                    ? null
                                    : _tasks.isFolded(task),
                                onFold: () => _tasks.setFolded(
                                  task,
                                  !_tasks.isFolded(task),
                                ),
                                onToggle: () => _toggle(task),
                                onOpen: () => _selectedTasks.isNotEmpty
                                    ? _toggleSelected(task)
                                    : _open(task),
                                // Beside the checkbox where a pointer reveals it
                                // on hover; at the row's end on touch screens.
                                leading: touch ? null : handle(index),
                                trailing: touch ? handle(index) : null,
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
                            () => _tasks.setCollapsed(
                              section,
                              !section.isCollapsed,
                            ),
                          ),
                          onAddTask: () => _addTaskTo(section),
                          onAction: (action) => _sectionAction(section, action),
                        ),
                      },
                    ),
                  ),
                ),
              ),
            if (sectionsAvailable)
              pad(
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
              ),
            if (done.isNotEmpty) ...[
              pad(
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      24,
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
              ),
              pad(
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
              ),
            ],
          ],
          // Room to scroll the last task clear of the capture bar.
          SliverToBoxAdapter(
            child: SizedBox(height: (capture == null ? _dockHeight : 0) + 24),
          ),
        ],
      ),
    );
  }
}

/// The side sheet's width beside the list.
const _editorWidth = 400.0;

/// Reports its child's size after layout, so the list can leave room for
/// the capture bar floating over it.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize render) {
    render.onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final measured = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(measured));
  }
}

/// Where no app bar names the project: how many tasks are open, and the
/// completed-tasks toggle beside them.
class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.count, required this.toggle});

  final String count;
  final Widget toggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          toggle,
        ],
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

/// The capture field's text, with the parts quick add recognises lit as
/// they are typed. Dismissed parts stay plain text.
class _QuickText extends TextEditingController {
  final ignore = <(int, int)>{};

  QuickTask get parsed =>
      parseQuickTask(text, now: DateTime.now(), ignore: ignore);

  void dismiss(QuickToken token) {
    ignore.add((token.start, token.end));
    notifyListeners();
  }

  @override
  set value(TextEditingValue next) {
    // A dismissal holds only while its text does.
    if (next.text != text) {
      ignore.removeWhere((r) => r.$2 > next.text.length);
    }
    super.value = next;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final tokens = parsed.tokens;
    if (tokens.isEmpty || value.composing.isValid && withComposing) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final primary = Theme.of(context).colorScheme.primary;
    final lit = style?.copyWith(
      color: primary,
      backgroundColor: primary.withValues(alpha: 0.14),
    );
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final t in tokens) {
      if (t.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, t.start)));
      }
      spans.add(TextSpan(text: text.substring(t.start, t.end), style: lit));
      cursor = t.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}

/// One field and one button, pinned under the list and above the keyboard.
/// Dates, times, `#project`, `@label`, `p1`–`p4` and `{deadline}` typed in
/// the text are recognised as you go.
class _QuickAdd extends StatefulWidget {
  const _QuickAdd({super.key, required this.projectName, required this.onAdd});

  final String projectName;

  /// Returns whether the task was added, so the field keeps its text on
  /// failure.
  final Future<bool> Function(
    QuickTask parsed,
    String raw,
    TaskPriority priority,
  )
  onAdd;

  @override
  State<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends State<_QuickAdd> {
  final _text = _QuickText();
  late final FocusNode _focus = FocusNode()
    ..addListener(() => setState(() => _focused = _focus.hasFocus));
  bool _focused = false;
  TaskPriority _priority = TaskPriority.p4;
  int _draftRevision = 0;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _text.text.trim();
    if (raw.isEmpty || _busy) return;
    final parsed = _text.parsed;
    final revision = _draftRevision;
    setState(() => _busy = true);
    final added = await widget.onAdd(parsed, raw, _priority);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (added && revision == _draftRevision) {
        _text.clear();
        _text.ignore.clear();
        _priority = TaskPriority.p4;
      }
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One panel: the field, its priority and the send button read
    // as a single control, edged in the accent while it has focus.
    return Panel(
      radius: 22,
      borderColor: _focused ? theme.colorScheme.primary : null,
      padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // What the text will set, each part dismissable back to text.
          ValueListenableBuilder(
            valueListenable: _text,
            builder: (context, _, _) {
              final tokens = _text.parsed.tokens;
              if (tokens.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final token in tokens)
                        InputChip(
                          avatar: Icon(_tokenIcon(token.kind), size: 16),
                          label: Text(token.text),
                          visualDensity: VisualDensity.compact,
                          deleteButtonTooltipMessage:
                              'نادیده گرفتن «${token.text}»',
                          onDeleted: () => _text.dismiss(token),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
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
                    hintText: 'افزودن کار…',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      4,
                      12,
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => _draftRevision++,
                ),
              ),
              PopupMenuButton<TaskPriority>(
                tooltip: 'اولویت: ${_priority.label}',
                initialValue: _priority,
                icon: Icon(
                  _priority == TaskPriority.p4
                      ? Icons.outlined_flag
                      : Icons.flag,
                  color: _priority == TaskPriority.p4
                      ? theme.colorScheme.onSurfaceVariant
                      : _priority.colorIn(context),
                ),
                onSelected: (p) => setState(() {
                  _priority = p;
                  _draftRevision++;
                }),
                itemBuilder: (context) => [
                  for (final p in TaskPriority.values)
                    PopupMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          Icon(Icons.flag, color: p.colorIn(context)),
                          const SizedBox(width: 12),
                          Text(p.label),
                        ],
                      ),
                    ),
                ],
              ),
              // Send wakes up once there is something to add.
              ValueListenableBuilder(
                valueListenable: _text,
                builder: (context, value, button) {
                  final ready = value.text.trim().isNotEmpty;
                  return AnimatedOpacity(
                    opacity: ready || _busy ? 1 : 0.55,
                    duration: Motion.of(context, Motion.quick),
                    child: button,
                  );
                },
                child: IconButton.filled(
                  tooltip: 'افزودن کار',
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                  ),
                  onPressed: _busy ? null : _submit,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _tokenIcon(QuickTokenKind kind) => switch (kind) {
  QuickTokenKind.date => Icons.event,
  QuickTokenKind.time => Icons.schedule,
  QuickTokenKind.priority => Icons.flag,
  QuickTokenKind.project => Icons.folder_outlined,
  QuickTokenKind.label => Icons.sell_outlined,
  QuickTokenKind.deadline => Icons.hourglass_bottom,
};

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
