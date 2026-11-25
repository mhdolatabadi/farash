import 'package:flutter/material.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/today_bento.dart';

/// The day's actual working area, instead of unrelated dashboard cards.
///
/// On phones the task queue starts immediately after the date; utilities go
/// after the work. Wide screens put the working list next to a real sidebar.
/// No task is moved between dates, counted as completed, or labelled with a
/// clock time without authoritative task data.
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
  final int? done;
  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final timed = [
      for (final task in todayTasks)
        if (task.due?.isTimed == true) task,
    ]..sort(
      (a, b) => a.due!.datetime!.compareTo(b.due!.datetime!),
    );
    final flexible = [
      for (final task in todayTasks)
        if (task.due?.isTimed != true) task,
    ];

    final work = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timed.isNotEmpty)
          _WorkSection(
            title: 'طبق ساعت',
            count: timed.length,
            children: [
              for (var index = 0; index < timed.length; index++)
                _TimedTask(
                  task: timed[index],
                  child: rowBuilder(timed[index], index == timed.length - 1),
                ),
            ],
          ),
        if (flexible.isNotEmpty)
          _WorkSection(
            title: 'در صف انجام',
            count: flexible.length,
            children: [
              for (var index = 0; index < flexible.length; index++)
                rowBuilder(flexible[index], index == flexible.length - 1),
            ],
          ),
        if (todayTasks.isEmpty)
          const _EmptyDay(),
        if (overdueTasks.isNotEmpty)
          _WorkSection(
            title: 'دیرشده',
            count: overdueTasks.length,
            late: true,
            action: TextButton.icon(
              onPressed: onMoveOverdue,
              icon: const Icon(Icons.event_repeat_outlined),
              label: const Text('انتقال همه به امروز'),
            ),
            children: [
              for (var index = 0; index < overdueTasks.length; index++)
                rowBuilder(
                  overdueTasks[index],
                  index == overdueTasks.length - 1,
                ),
            ],
          ),
      ],
    );

    final companion = _DayCompanion(
      open: todayTasks.length + overdueTasks.length,
      done: done,
      focus: focus,
      onOpenFocus: onOpenFocus,
      habits: habits,
      onOpenHabits: onOpenHabits,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= 860 && scale < 1.5;
        final masthead = _DateMasthead(today: today, compact: !split);
        if (!split) {
          return Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                masthead,
                const SizedBox(height: Space.xl),
                work,
                const SizedBox(height: Space.xl),
                companion,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.xl,
            Space.lg,
            Space.xl,
            Space.xxl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    masthead,
                    const SizedBox(height: Space.xl),
                    work,
                  ],
                ),
              ),
              const SizedBox(width: Space.xxl),
              SizedBox(
                width: 248,
                child: companion,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DateMasthead extends StatelessWidget {
  const _DateMasthead({required this.today, required this.compact});

  final DateTime today;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = formatDate(
      today,
      CalendarScope.of(context),
      today: today,
      alwaysYear: true,
    ).split(' ');
    final weekday = weekdayNames[today.weekday - 1];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final dayWidth = scale >= 1.5 ? 58.0 : 74.0;

    return Semantics(
      header: true,
      label: '$weekday ${date.join(' ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: dayWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                date.first,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 64 : 80,
                  height: 1,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Container(
            width: 1,
            height: 48,
            color: colors.outlineVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weekday,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  date.skip(1).join(' '),
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkSection extends StatelessWidget {
  const _WorkSection({
    required this.title,
    required this.count,
    required this.children,
    this.action,
    this.late = false,
  });

  final String title;
  final int count;
  final List<Widget> children;
  final Widget? action;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
      color: late ? colors.error : colors.onSurface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: titleStyle),
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    persianDigits(count),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              ?action,
            ],
          ),
          const SizedBox(height: Space.sm),
          ...children,
        ],
      ),
    );
  }
}

class _TimedTask extends StatelessWidget {
  const _TimedTask({required this.task, required this.child});

  final Task task;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final time = task.due?.localTime;
    if (time == null) return child;
    final text = formatTime(time);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final timeLabel = Text(
      text,
      textDirection: TextDirection.ltr,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (scale >= 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: Space.xs,
              top: Space.sm,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: timeLabel,
            ),
          ),
          child,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 65,
          child: Padding(
            padding: const EdgeInsets.only(top: Space.lg),
            child: timeLabel,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: Space.md),
          Text(
            'برای امروز کاری نمانده؛ از کادر پایین کار تازه‌ای اضافه کنید.',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// Secondary information lives outside the work queue, never ahead of it.
class _DayCompanion extends StatelessWidget {
  const _DayCompanion({
    required this.open,
    required this.done,
    this.focus,
    this.onOpenFocus,
    this.habits,
    this.onOpenHabits,
  });

  final int open;
  final int? done;
  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final total = open + (done ?? 0);
    final progress = done == null || total == 0 ? null : done! / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'مرور روز',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: Space.sm),
        Semantics(
          label: done == null
              ? '${persianDigits(open)} کار باز برای امروز'
              : '${persianDigits(done!)} کار از ${persianDigits(total)} کار امروز انجام شد',
          excludeSemantics: true,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  done == null
                      ? '${persianDigits(open)} کار باقی‌مانده'
                      : '${persianDigits(done!)} از ${persianDigits(total)} انجام‌شده',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: Space.md),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colors.outlineVariant,
          ),
        ],
        if (focus case final controller?) ...[
          const SizedBox(height: Space.lg),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final seconds = (controller.remaining.inMilliseconds / 1000)
                  .ceil();
              final clock = persianDigits(
                '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
              );
              return Semantics(
                button: true,
                label: 'باز کردن تمرکز',
                excludeSemantics: true,
                child: Material(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onOpenFocus,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Space.md,
                        Space.md,
                        Space.md,
                        Space.md,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timelapse_outlined,
                            color: colors.onPrimaryContainer,
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: Text(
                              controller.running ? 'تمرکز در جریان' : 'شروع تمرکز',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            clock,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
        if (habits case final controller?) ...[
          const SizedBox(height: Space.lg),
          TodayHabitsStrip(
            controller: controller,
            onOpen: onOpenHabits,
          ),
        ],
      ],
    );
  }
}
