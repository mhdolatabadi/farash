import 'package:flutter/material.dart';
import 'package:farash/features/tasks/data/task.dart';

/// One task row: a round checkbox in the priority color, the title and the
/// first line of the description.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    this.trailing,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.isCompleted;
    final firstLine = task.description.trim().split('\n').first;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PriorityCheck(task: task, onToggle: onToggle),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                  ],
                ),
              ),
            ),
            if (task.priority != TaskPriority.p4)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 15, end: 6),
                child: Text(
                  'P${task.priority.index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: task.priority.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ?trailing,
          ],
        ),
      ),
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
