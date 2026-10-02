import 'package:flutter/material.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/checklist.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

/// What the detail sheet asks the list to do after it closes.
enum TaskSheetResult { saved, deleted }

/// Opens the editor for [task]. [projects] are the places it may move to.
Future<TaskSheetResult?> showTaskDetailSheet(
  BuildContext context, {
  required TasksController controller,
  required Task task,
  required List<Project> projects,
}) {
  return showModalBottomSheet<TaskSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => TaskDetailEditor(
      controller: controller,
      task: task,
      projects: projects,
    ),
  );
}

class TaskDetailEditor extends StatefulWidget {
  const TaskDetailEditor({
    super.key,
    this.onResult,
    required this.controller,
    required this.task,
    required this.projects,
  });

  final ValueChanged<TaskSheetResult?>? onResult;
  final TasksController controller;
  final Task task;
  final List<Project> projects;

  @override
  State<TaskDetailEditor> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task.title);
  late final _description = TextEditingController(
    text: widget.task.description,
  );
  late TaskPriority _priority = widget.task.priority;
  late String _projectId = widget.task.projectId;
  late String? _sectionId = widget.controller.sectionOf(widget.task);
  late TaskDates _dates = widget.task.dates;

  Future<void> _pickDates() async {
    final picked = await showDuePicker(context, initial: _dates);
    if (picked != null && mounted) setState(() => _dates = picked);
  }

  final _newSubtask = TextEditingController();
  final _newItem = TextEditingController();
  bool _saving = false;

  /// The task as the list has it now; subtasks and moves change it while
  /// the sheet is open.
  Task get _task => widget.controller.taskById(widget.task.id) ?? widget.task;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _newSubtask.dispose();
    _newItem.dispose();
    super.dispose();
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) showTaskError(context, error);
    }
  }

  /// Checklist changes save at once, like ticking a box should.
  Future<void> _saveChecklist(String description) {
    _description.text = description;
    return _quietly(
      () => widget.controller.saveDescription(widget.task, description),
    );
  }

  Future<void> _addItem() async {
    final text = _newItem.text.trim();
    if (text.isEmpty) return;
    _newItem.clear();
    await _saveChecklist(addChecklistItem(_description.text, text));
  }

  Future<void> _addSubtask() async {
    final title = _newSubtask.text.trim();
    if (title.isEmpty) return;
    try {
      await widget.controller.add(title, parent: _task);
      _newSubtask.clear();
    } catch (error) {
      if (mounted) showTaskError(context, error);
    }
  }

  Future<void> _openSubtask(Task subtask) async {
    final result = await showTaskDetailSheet(
      context,
      controller: widget.controller,
      task: subtask,
      projects: widget.projects,
    );
    if (result == TaskSheetResult.deleted) {
      await _quietly(() => widget.controller.delete(subtask));
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await widget.controller.edit(
        widget.task,
        title: _title.text,
        description: _description.text,
        priority: _priority,
        projectId: _projectId,
        sectionId: _sectionId,
        dates: _dates,
      );
      if (mounted) _close(TaskSheetResult.saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTaskError(context, error);
    }
  }

  void _close(TaskSheetResult? result) {
    if (widget.onResult != null) {
      widget.onResult!(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targets = [
      for (final p in widget.projects)
        if (!p.isFolder && !p.isArchived) p,
    ];
    // The current project stays selectable even if it is now archived.
    if (!targets.any((p) => p.id == _projectId)) {
      final current = widget.projects
          .where((p) => p.id == _projectId)
          .firstOrNull;
      if (current != null) targets.insert(0, current);
    }
    return GlassSurface(
      radius: 24,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'جزئیات کار',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'بستن ویرایشگر',
                      onPressed: _saving ? null : () => _close(null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  style: theme.textTheme.titleMedium,
                  decoration: const InputDecoration(labelText: 'عنوان'),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'عنوان کار را بنویسید.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  maxLength: 20000,
                  minLines: 3,
                  maxLines: 10,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                    alignLabelWithHint: true,
                  ),
                ),
                _Checklist(
                  description: _description,
                  newItem: _newItem,
                  onChanged: _saveChecklist,
                  onAdd: _addItem,
                ),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => _Subtasks(
                    controller: widget.controller,
                    task: _task,
                    newSubtask: _newSubtask,
                    onAdd: _addSubtask,
                    onOpen: _openSubtask,
                    onToggle: (t) => _quietly(
                      () => widget.controller.setCompleted(t, !t.isCompleted),
                    ),
                    onIndent: () =>
                        _quietly(() => widget.controller.indent(_task)),
                    onOutdent: () =>
                        _quietly(() => widget.controller.outdent(_task)),
                  ),
                ),
                const SizedBox(height: 12),
                _ScheduleRow(dates: _dates, onTap: _pickDates),
                const SizedBox(height: 12),
                Text('اولویت', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                PriorityPicker(
                  value: _priority,
                  onChanged: (p) => setState(() => _priority = p),
                ),
                const SizedBox(height: 16),
                if (targets.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'پروژه'),
                    items: [
                      for (final p in targets)
                        DropdownMenuItem(
                          value: p.id,
                          child: Row(
                            children: [
                              Icon(
                                p.isInbox ? Icons.inbox_outlined : Icons.circle,
                                size: p.isInbox ? 18 : 10,
                                color: p.isInbox ? null : p.swatch,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() {
                      _projectId = id!;
                      // Sections belong to one project.
                      if (_projectId != widget.task.projectId) {
                        _sectionId = null;
                      }
                    }),
                  ),
                // A subtask stays in its parent's section.
                if (_projectId == widget.task.projectId &&
                    widget.task.parentId == null &&
                    widget.controller.sections.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _sectionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'بخش'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('بدون بخش'),
                      ),
                      for (final section in widget.controller.sections)
                        DropdownMenuItem<String?>(
                          value: section.id,
                          child: Text(
                            section.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) => setState(() => _sectionId = id),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _close(TaskSheetResult.deleted),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('حذف'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('ذخیره'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four flags, P1 to P4.
class PriorityPicker extends StatelessWidget {
  const PriorityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TaskPriority value;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in TaskPriority.values)
          ChoiceChip(
            selected: p == value,
            onSelected: (_) => onChanged(p),
            avatar: Icon(Icons.flag, color: p.color, size: 18),
            label: Text(p.label),
            showCheckmark: false,
          ),
      ],
    );
  }
}

/// Checklist items found in the description, ticked in place, and a field
/// that adds one.
class _Checklist extends StatelessWidget {
  const _Checklist({
    required this.description,
    required this.newItem,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController description;
  final TextEditingController newItem;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: description,
      builder: (context, value, _) {
        final items = parseChecklist(value.text);
        final done = items.where((i) => i.done).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'چک‌لیست ${persianDigits(done)}/${persianDigits(items.length)}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            for (final item in items)
              CheckboxListTile(
                key: ValueKey('checklist-${item.line}'),
                value: item.done,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  item.text,
                  style: item.done
                      ? TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                ),
                onChanged: (checked) => onChanged(
                  setChecklistItem(value.text, item.line, checked ?? false),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: newItem,
                    maxLength: 500,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'مورد تازهٔ چک‌لیست',
                      isDense: true,
                    ),
                    onSubmitted: (_) => onAdd(),
                  ),
                ),
                IconButton(
                  tooltip: 'افزودن به چک‌لیست',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_task),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The task's subtasks with progress, a field that adds one, and the
/// actions that nest the task under the one above it or lift it a level.
class _Subtasks extends StatelessWidget {
  const _Subtasks({
    required this.controller,
    required this.task,
    required this.newSubtask,
    required this.onAdd,
    required this.onOpen,
    required this.onToggle,
    required this.onIndent,
    required this.onOutdent,
  });

  final TasksController controller;
  final Task task;
  final TextEditingController newSubtask;
  final VoidCallback onAdd;
  final ValueChanged<Task> onOpen;
  final ValueChanged<Task> onToggle;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parent = controller.taskById(task.parentId);
    final above = controller.indentTarget(task);
    final children = controller.openChildren(task);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parent != null)
          Text(
            'زیرکارِ «${parent.title}»',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            if (above != null && !task.isCompleted)
              TextButton.icon(
                onPressed: onIndent,
                icon: const Icon(Icons.format_indent_increase),
                label: const Text('زیرکارِ کار بالایی'),
              ),
            if (parent != null)
              TextButton.icon(
                onPressed: onOutdent,
                icon: const Icon(Icons.format_indent_decrease),
                label: const Text('یک سطح بیرون'),
              ),
          ],
        ),
        Text(
          task.hasSubtasks
              ? 'زیرکارها ${persianDigits(task.completedSubtaskCount)}/${persianDigits(task.subtaskCount)}'
              : 'زیرکارها',
          style: theme.textTheme.labelLarge,
        ),
        for (final child in children)
          TaskTile(
            key: ValueKey('subtask-${child.id}'),
            task: child,
            onToggle: () => onToggle(child),
            onOpen: () => onOpen(child),
          ),
        if (!task.isCompleted)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: newSubtask,
                  maxLength: 500,
                  buildCounter:
                      (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) => null,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'زیرکار تازه',
                    isDense: true,
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              IconButton(
                tooltip: 'افزودن زیرکار',
                onPressed: onAdd,
                icon: const Icon(Icons.subdirectory_arrow_left),
              ),
            ],
          ),
      ],
    );
  }
}

/// The dates in one line; tapping opens the scheduler.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.dates, required this.onTap});

  final TaskDates dates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = describeDates(dates, CalendarScope.of(context));
    return Semantics(
      button: true,
      label: 'زمان‌بندی: $text',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(Icons.event, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_left),
            ],
          ),
        ),
      ),
    );
  }
}
