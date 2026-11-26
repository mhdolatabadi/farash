import 'package:flutter/material.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/tasks/data/task.dart';

/// A quiet, single-column task list for Today, with subtle elevation.
///
/// There are no time lanes, category headings, calendar strip, statistics,
/// companion panels, Focus shortcuts, or decorative cards. Timed tasks keep
/// their actual due time in each task row; unscheduled tasks follow them.
/// Overdue tasks remain actionable without being put into another section.
class TodayWorkspace extends StatelessWidget {
  const TodayWorkspace({
    super.key,
    required this.today,
    required this.todayTasks,
    required this.overdueTasks,
    required this.rowBuilder,
    required this.onMoveOverdue,
    this.done,
    this.focus,
    this.onOpenFocus,
    this.habits,
    this.onOpenHabits,
  });

  final DateTime today;
  final List<Task> todayTasks;
  final List<Task> overdueTasks;
  final Widget Function(Task task, bool last) rowBuilder;
  final VoidCallback onMoveOverdue;

  // These parameters are retained for compatibility with existing callers,
  // but deliberately have no place in this minimal view.
  final int? done;
  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  Widget build(BuildContext context) {
    final todayOrdered = [...todayTasks]
      ..sort((a, b) {
        final aTime = a.due?.datetime;
        final bTime = b.due?.datetime;
        if (aTime != null && bTime != null) return aTime.compareTo(bTime);
        if (aTime != null) return -1;
        if (bTime != null) return 1;
        return 0;
      });
    final tasks = [...todayOrdered, ...overdueTasks];
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.xxl,
      ),
      child: SoftWell(
        radius: 36,
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.md,
          Space.xl,
          Space.md,
          Space.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xl),
                child: Text(
                  'کاری برای امروز نمانده.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var index = 0; index < tasks.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Material(
                    color: colors.surface,
                    elevation: 3,
                    shadowColor: colors.shadow.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: rowBuilder(tasks[index], index == tasks.length - 1),
                  ),
                ),
            if (overdueTasks.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onMoveOverdue,
                  child: const Text('انتقال کارهای عقب‌افتاده به امروز'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
