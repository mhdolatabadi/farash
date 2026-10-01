import 'package:flutter/material.dart';
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
    builder: (context) => _TaskDetailSheet(
      controller: controller,
      task: task,
      projects: projects,
    ),
  );
}

class _TaskDetailSheet extends StatefulWidget {
  const _TaskDetailSheet({
    required this.controller,
    required this.task,
    required this.projects,
  });

  final TasksController controller;
  final Task task;
  final List<Project> projects;

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.task.title);
  late final _description = TextEditingController(
    text: widget.task.description,
  );
  late TaskPriority _priority = widget.task.priority;
  late String _projectId = widget.task.projectId;
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
    final navigator = Navigator.of(context);
    try {
      await widget.controller.edit(
        widget.task,
        title: _title.text,
        description: _description.text,
        priority: _priority,
        projectId: _projectId,
      );
      navigator.pop(TaskSheetResult.saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTaskError(context, error);
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
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                  onChanged: (id) => setState(() => _projectId = id!),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, TaskSheetResult.deleted),
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
