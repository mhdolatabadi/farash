import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

/// Readable width for the task list on wide screens.
const _maxListWidth = 760.0;

/// A project's tasks with quick add at the bottom.
class ProjectTasksView extends StatefulWidget {
  const ProjectTasksView({
    super.key,
    required this.project,
    required this.api,
    required this.token,
    required this.moveTargets,
  });

  final Project project;
  final TasksApi api;
  final String? Function() token;

  /// The projects a task may move to.
  final List<Project> Function() moveTargets;

  @override
  State<ProjectTasksView> createState() => _ProjectTasksViewState();
}

class _ProjectTasksViewState extends State<ProjectTasksView> {
  late final TasksController _tasks = TasksController(
    api: widget.api,
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

  Future<void> _open(Task task) async {
    final result = await showTaskDetailSheet(
      context,
      controller: _tasks,
      task: task,
      projects: widget.moveTargets(),
    );
    if (result == TaskSheetResult.deleted) await _delete(task);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.project.isFolder) return const _FolderNotice();
    return Column(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: _tasks,
            builder: (context, _) => _list(context),
          ),
        ),
        _QuickAdd(
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
      ],
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
    final open = _tasks.openTasks;
    final done = _tasks.completedTasks;
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
                  child: Align(
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
              if (open.isEmpty && done.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'هنوز کاری در «${widget.project.displayName}» نیست.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              SliverReorderableList(
                itemCount: open.length,
                onReorderItem: (from, to) =>
                    _run(() => _tasks.reorder(from, to)),
                itemBuilder: (context, index) {
                  final task = open[index];
                  return Material(
                    key: ValueKey(task.id),
                    color: Colors.transparent,
                    child: TaskTile(
                      task: task,
                      onToggle: () => _toggle(task),
                      onOpen: () => _open(task),
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
                  );
                },
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
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxListWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
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
