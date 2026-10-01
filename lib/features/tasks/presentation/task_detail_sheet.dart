import 'package:flutter/material.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
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
                      if (_projectId != widget.task.projectId)
                        _sectionId = null;
                    }),
                  ),
                if (_projectId == widget.task.projectId &&
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
