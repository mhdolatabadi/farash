import 'package:flutter/material.dart';
import 'package:farash/features/tasks/data/task.dart';

enum SectionAction { rename, moveUp, moveDown, delete }

enum SectionDeleteChoice { keepTasks, withTasks }

/// The header of a section in the task list: collapse, name, task count, a
/// button to add a task into it, and its menu.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.section,
    required this.taskCount,
    required this.isFirst,
    required this.isLast,
    required this.onToggle,
    required this.onAddTask,
    required this.onAction,
  });

  final Section section;
  final int taskCount;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onToggle;
  final VoidCallback onAddTask;
  final ValueChanged<SectionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collapsed = section.isCollapsed;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(top: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: collapsed ? 'باز کردن بخش' : 'بستن بخش',
                onPressed: onToggle,
                icon: AnimatedRotation(
                  turns: collapsed ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.expand_more),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: section.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (taskCount > 0)
                            TextSpan(
                              text: '  $taskCount',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'افزودن کار به «${section.name}»',
                onPressed: onAddTask,
                icon: const Icon(Icons.add),
              ),
              PopupMenuButton<SectionAction>(
                tooltip: 'گزینه‌های بخش',
                onSelected: onAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: SectionAction.rename,
                    child: Text('تغییر نام'),
                  ),
                  if (!isFirst)
                    const PopupMenuItem(
                      value: SectionAction.moveUp,
                      child: Text('انتقال به بالا'),
                    ),
                  if (!isLast)
                    const PopupMenuItem(
                      value: SectionAction.moveDown,
                      child: Text('انتقال به پایین'),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: SectionAction.delete,
                    child: Text('حذف بخش'),
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

/// Asks for a section name; null when cancelled.
Future<String?> askSectionName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => _askText(
  context,
  title: title,
  label: 'نام بخش',
  action: initial.isEmpty ? 'افزودن' : 'ذخیره',
  initial: initial,
  maxLength: 120,
);

/// Asks for the title of a task to add into [sectionName].
Future<String?> askTaskTitle(BuildContext context, String sectionName) =>
    _askText(
      context,
      title: 'کار تازه در «$sectionName»',
      label: 'عنوان',
      action: 'افزودن',
      maxLength: 500,
    );

Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  required int maxLength,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextDialog(
      title: title,
      label: label,
      action: action,
      initial: initial,
      maxLength: maxLength,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.action,
    required this.initial,
    required this.maxLength,
  });

  final String title;
  final String label;
  final String action;
  final String initial;
  final int maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _text.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _text,
          autofocus: true,
          maxLength: widget.maxLength,
          decoration: InputDecoration(labelText: widget.label),
          onFieldSubmitted: (_) => _submit(),
          validator: (value) => (value ?? '').trim().isEmpty
              ? '${widget.label} را بنویسید.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Asks how to delete a section; null when cancelled.
Future<SectionDeleteChoice?> confirmSectionDelete(
  BuildContext context,
  Section section, {
  required int taskCount,
}) {
  return showDialog<SectionDeleteChoice>(
    context: context,
    builder: (context) {
      final error = Theme.of(context).colorScheme.error;
      return AlertDialog(
        title: Text('حذف بخش «${section.name}»؟'),
        content: Text(
          taskCount == 0
              ? 'این بخش کاری ندارد.'
              : 'کارهای این بخش در پروژه بمانند یا با بخش حذف شوند؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          if (taskCount > 0)
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, SectionDeleteChoice.withTasks),
              style: TextButton.styleFrom(foregroundColor: error),
              child: const Text('حذف با کارها'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, SectionDeleteChoice.keepTasks),
            child: Text(taskCount == 0 ? 'حذف' : 'حذف و نگه‌داشتن کارها'),
          ),
        ],
      );
    },
  );
}
