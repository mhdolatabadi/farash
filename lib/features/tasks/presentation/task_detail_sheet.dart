import 'package:flutter/material.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/checklist.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/priority_color.dart';
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

  /// A field without a box: the sheet's structure comes from spacing and
  /// dividers, so the title and notes read as content.
  static InputDecoration _bare(ThemeData theme, String label) =>
      InputDecoration(
        hintText: label,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      );

  /// A dropdown that reads as the value of a property row.
  static const _bareChoice = InputDecoration(
    filled: false,
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    contentPadding: EdgeInsets.symmetric(vertical: 12),
  );

  /// Counters only matter close to the limit.
  static Widget? _counterNearLimit(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) => maxLength == null || currentLength < maxLength * 0.9
      ? null
      : Text(
          '${persianDigits(currentLength)}/${persianDigits(maxLength)}',
          style: Theme.of(context).textTheme.labelSmall,
        );

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
    // Beside the list the editor is a side sheet of glass; as a modal
    // bottom sheet it is the sheet itself, over a scrim, with no pane of
    // its own.
    final side = widget.onResult != null;
    final body = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A side sheet keeps its actions at the bottom edge; a bottom
          // sheet is as tall as its content.
          Flexible(
            fit: side ? FlexFit.tight : FlexFit.loose,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The title is the sheet's heading, not a form box.
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('task-title'),
                          controller: _title,
                          maxLength: 500,
                          buildCounter: _counterNearLimit,
                          minLines: 1,
                          maxLines: 4,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontFamily: 'Vazirmatn',
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: _bare(theme, 'عنوان کار'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'عنوان کار را بنویسید.'
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'بستن ویرایشگر',
                        onPressed: _saving ? null : () => _close(null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: TextFormField(
                      controller: _description,
                      maxLength: 20000,
                      buildCounter: _counterNearLimit,
                      minLines: 2,
                      maxLines: 10,
                      keyboardType: TextInputType.multiline,
                      style: theme.textTheme.bodyLarge,
                      decoration: _bare(theme, 'توضیحات'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _ScheduleRow(dates: _dates, onTap: _pickDates),
                  _PropertyRow(
                    icon: Icons.flag_outlined,
                    label: 'اولویت',
                    child: PriorityPicker(
                      value: _priority,
                      onChanged: (p) => setState(() => _priority = p),
                    ),
                  ),
                  if (targets.isNotEmpty)
                    _PropertyRow(
                      icon: Icons.folder_outlined,
                      label: 'پروژه',
                      expand: true,
                      child: DropdownButtonFormField<String>(
                        initialValue: _projectId,
                        isExpanded: true,
                        decoration: _bareChoice,
                        items: [
                          for (final p in targets)
                            DropdownMenuItem(
                              value: p.id,
                              child: Row(
                                children: [
                                  Icon(
                                    p.isInbox
                                        ? Icons.inbox_outlined
                                        : Icons.circle,
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
                    ),
                  // A subtask stays in its parent's section.
                  if (_projectId == widget.task.projectId &&
                      widget.task.parentId == null &&
                      widget.controller.sections.isNotEmpty)
                    _PropertyRow(
                      icon: Icons.view_agenda_outlined,
                      label: 'بخش',
                      expand: true,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _sectionId,
                        isExpanded: true,
                        decoration: _bareChoice,
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
                    ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  _Checklist(
                    description: _description,
                    newItem: _newItem,
                    onChanged: _saveChecklist,
                    onAdd: _addItem,
                  ),
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
                ],
              ),
            ),
          ),
          // The actions stay in reach however long the task is: delete
          // apart at the start, the one primary action at the end.
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                12,
                8,
                16,
                8 + (side ? 0 : MediaQuery.paddingOf(context).bottom),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'حذف کار',
                    onPressed: _saving
                        ? null
                        : () => _close(TaskSheetResult.deleted),
                    color: theme.colorScheme.error,
                    icon: const Icon(Icons.delete_outline),
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
            ),
          ),
        ],
      ),
    );
    if (side) return GlassSurface(child: body);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: body,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final vertical =
            constraints.maxWidth < 320 &&
            MediaQuery.textScalerOf(context).scale(14) > 18;
        return SegmentedButton<TaskPriority>(
          direction: vertical ? Axis.vertical : Axis.horizontal,
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.padded,
            minimumSize: WidgetStatePropertyAll(Size(48, 48)),
            // A stadium turns into an oval when the segments stack.
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          segments: [
            for (final p in TaskPriority.values)
              ButtonSegment(
                value: p,
                tooltip: p.label,
                icon: Icon(
                  p == TaskPriority.p4 ? Icons.outlined_flag : Icons.flag,
                  size: 18,
                  color: p.colorIn(context),
                ),
                label: Text(persianDigits(p.level)),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.single),
        );
      },
    );
  }
}

/// A section title in the editor, with an optional count beside it.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// A one-line field with its add button, for checklist items and
/// subtasks.
class _InlineAdd extends StatelessWidget {
  const _InlineAdd({
    required this.controller,
    required this.hint,
    required this.tooltip,
    required this.icon,
    required this.onAdd,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final String tooltip;
  final IconData icon;
  final VoidCallback onAdd;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            maxLength: 500,
            buildCounter:
                (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: hint, isDense: true),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        IconButton(tooltip: tooltip, onPressed: onAdd, icon: Icon(icon)),
      ],
    );
  }
}

/// Checklist items found in the description, ticked in place. The field
/// that adds one opens on demand, so an empty checklist takes one line.
class _Checklist extends StatefulWidget {
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
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: widget.description,
      builder: (context, value, _) {
        final items = parseChecklist(value.text);
        final done = items.where((i) => i.done).length;
        if (items.isEmpty && !_adding) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _adding = true),
              icon: const Icon(Icons.checklist),
              label: const Text('افزودن چک‌لیست'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeading(
              items.isEmpty
                  ? 'چک‌لیست'
                  : 'چک‌لیست ${persianDigits(done)}/${persianDigits(items.length)}',
            ),
            for (final item in items)
              CheckboxListTile(
                key: ValueKey('checklist-${item.line}'),
                value: item.done,
                dense: true,
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
                onChanged: (checked) => widget.onChanged(
                  setChecklistItem(value.text, item.line, checked ?? false),
                ),
              ),
            _InlineAdd(
              controller: widget.newItem,
              hint: 'مورد تازهٔ چک‌لیست',
              tooltip: 'افزودن به چک‌لیست',
              icon: Icons.add_task,
              onAdd: widget.onAdd,
              autofocus: items.isEmpty,
            ),
          ],
        );
      },
    );
  }
}

/// The task's subtasks with progress, a field that adds one (opened on
/// demand), and the actions that nest the task or lift it a level.
class _Subtasks extends StatefulWidget {
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
  State<_Subtasks> createState() => _SubtasksState();
}

class _SubtasksState extends State<_Subtasks> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final parent = widget.controller.taskById(task.parentId);
    final above = widget.controller.indentTarget(task);
    final children = widget.controller.openChildren(task);
    final showList = task.hasSubtasks || children.isNotEmpty || _adding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showList) ...[
          _SectionHeading(
            task.hasSubtasks
                ? 'زیرکارها ${persianDigits(task.completedSubtaskCount)}/${persianDigits(task.subtaskCount)}'
                : 'زیرکارها',
          ),
          for (final child in children)
            TaskTile(
              key: ValueKey('subtask-${child.id}'),
              task: child,
              onToggle: () => widget.onToggle(child),
              onOpen: () => widget.onOpen(child),
            ),
          if (!task.isCompleted)
            _InlineAdd(
              controller: widget.newSubtask,
              hint: 'زیرکار تازه',
              tooltip: 'افزودن زیرکار',
              icon: Icons.subdirectory_arrow_left,
              onAdd: widget.onAdd,
              autofocus: _adding && children.isEmpty,
            ),
        ],
        if (parent != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'زیرکارِ «${parent.title}»',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Wrap(
          spacing: 4,
          children: [
            if (!showList && !task.isCompleted)
              TextButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(Icons.subdirectory_arrow_left),
                label: const Text('افزودن زیرکار'),
              ),
            if (above != null && !task.isCompleted)
              TextButton.icon(
                onPressed: widget.onIndent,
                icon: const Icon(Icons.format_indent_increase),
                label: const Text('زیرکارِ کار بالایی'),
              ),
            if (parent != null)
              TextButton.icon(
                onPressed: widget.onOutdent,
                icon: const Icon(Icons.format_indent_decrease),
                label: const Text('یک سطح بیرون'),
              ),
          ],
        ),
      ],
    );
  }
}

/// A labelled property of the task: an icon, its name, and the control.
class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.icon,
    required this.label,
    required this.child,
    this.expand = false,
  });

  final IconData icon;
  final String label;
  final Widget child;

  /// Lets the control take the row's remaining width, as a dropdown does.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(label, style: theme.textTheme.bodyLarge),
            ],
          );
          if (!expand && constraints.maxWidth < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, const SizedBox(height: 8), child],
            );
          }
          return Row(
            children: [
              heading,
              const SizedBox(width: 12),
              Expanded(child: child),
            ],
          );
        },
      ),
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
              Icon(Icons.event, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Points toward the end in either direction.
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
