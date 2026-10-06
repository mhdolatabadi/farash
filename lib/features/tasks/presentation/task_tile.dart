import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/checklist.dart';
import 'package:farash/features/tasks/data/task.dart';

/// Indent per subtask level. Five levels stay usable at 320 px.
const subtaskIndent = 20.0;

/// One task row: a round checkbox in the priority color, the title, the
/// first line of the description, and subtask and checklist progress.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    this.trailing,
    this.leading,
    this.depth = 0,
    this.folded,
    this.onFold,
    this.onLongPress,
    this.selected = false,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final Widget? trailing;

  /// Shown before the checkbox, such as a drag handle on wide screens.
  final Widget? leading;

  /// 0 for a top-level task, 1 for its subtasks, and so on.
  final int depth;

  /// Whether the open subtasks are hidden; null when there are none to show.
  final bool? folded;
  final VoidCallback? onFold;

  /// Starts selecting several tasks.
  final VoidCallback? onLongPress;

  /// Picked for a bulk change.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.isCompleted;
    final firstLine = descriptionPreview(task.description);
    final checklist = parseChecklist(task.description);
    final dated = task.due != null || task.deadline != null;
    final row = InkWell(
      onTap: onOpen,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          8 + subtaskIndent * depth,
          4,
          4,
          4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?leading,
            _PriorityCheck(task: task, onToggle: onToggle),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (firstLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        firstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (task.hasSubtasks || checklist.isNotEmpty || dated) ...[
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task.hasSubtasks)
                            _SubtaskProgress(
                              task: task,
                              folded: folded,
                              onFold: onFold,
                            ),
                          if (checklist.isNotEmpty)
                            _Count(
                              icon: Icons.checklist,
                              label: 'چک‌لیست',
                              done: checklist.where((i) => i.done).length,
                              total: checklist.length,
                            ),
                          if (dated) TaskDateLabels(task: task),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    return Semantics(
      selected: selected,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          // A hairline from the title's edge keeps rows apart without boxes.
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: 56 + subtaskIndent * depth,
              end: 12,
            ),
            child: Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// "۲/۵" subtasks done; a button that folds the subtasks when there are open
/// ones to show.
class _SubtaskProgress extends StatelessWidget {
  const _SubtaskProgress({required this.task, this.folded, this.onFold});

  final Task task;
  final bool? folded;
  final VoidCallback? onFold;

  @override
  Widget build(BuildContext context) {
    final count = _Count(
      icon: folded == null
          ? Icons.subdirectory_arrow_left
          : folded!
          ? Icons.expand_more
          : Icons.expand_less,
      label: 'زیرکار',
      done: task.completedSubtaskCount,
      total: task.subtaskCount,
    );
    if (folded == null || onFold == null) return count;
    return Tooltip(
      message: folded! ? 'نمایش زیرکارها' : 'پنهان کردن زیرکارها',
      child: InkWell(
        onTap: onFold,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Align(
            widthFactor: 1,
            alignment: AlignmentDirectional.centerStart,
            child: count,
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.icon,
    required this.label,
    required this.done,
    required this.total,
  });

  final IconData icon;
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final text = '${persianDigits(done)}/${persianDigits(total)}';
    return Semantics(
      label: '$label: ${persianDigits(done)} از ${persianDigits(total)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// The due day (with time and duration) and the deadline; red once they
/// have passed on an open task.
class TaskDateLabels extends StatelessWidget {
  const TaskDateLabels({super.key, required this.task, this.now});

  final Task task;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = CalendarScope.of(context);
    final current = now ?? DateTime.now();
    final due = task.due;
    final deadline = task.deadline == null
        ? null
        : parseDateKey(task.deadline!);

    Widget label(IconData icon, String text, String name, bool late) {
      final overdue = late && !task.isCompleted;
      final color = overdue
          ? theme.colorScheme.error
          : theme.colorScheme.onSurfaceVariant;
      return Semantics(
        label: '${overdue ? 'دیرشده، ' : ''}$name: $text',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 12,
      children: [
        if (due != null)
          label(
            due.isTimed ? Icons.schedule : Icons.event,
            [
              relativeDay(due.day, settings, today: current),
              if (due.isTimed) formatTime(due.localTime!),
              if (task.durationMinutes != null)
                '· ${formatDuration(task.durationMinutes!)}',
            ].join(' '),
            'موعد',
            due.isOverdue(current),
          ),
        if (deadline != null)
          label(
            Icons.hourglass_bottom,
            'مهلت ${formatDate(deadline, settings, today: current)}',
            'مهلت',
            deadline.isBefore(dayOf(current)),
          ),
      ],
    );
  }
}

class _PriorityCheck extends StatelessWidget {
  const _PriorityCheck({required this.task, required this.onToggle});

  final Task task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final color = task.priority.color;
    final done = task.isCompleted;
    return Semantics(
      checked: done,
      label: done ? 'برگرداندن «${task.title}»' : 'انجام «${task.title}»',
      child: InkResponse(
        onTap: onToggle,
        radius: 24,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? color
                    : color.withValues(
                        alpha: task.priority == TaskPriority.p4 ? 0 : 0.12,
                      ),
                border: Border.all(color: color, width: 2),
              ),
              child: done
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
