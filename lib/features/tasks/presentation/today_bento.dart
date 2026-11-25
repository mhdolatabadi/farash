import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/habits/habit.dart';
import 'package:menval/features/habits/habits_controller.dart';

/// The daily brief keeps tasks visually ahead of supporting tools.
/// The date is typography, not another decorative dashboard card.
class TodayBento extends StatelessWidget {
  const TodayBento({
    super.key,
    required this.today,
    required this.open,
    this.done,
    this.focus,
    this.onOpenFocus,
    this.habits,
    this.onOpenHabits,
  });

  final DateTime today;
  final int open;
  final int? done;
  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 600 || scale >= 1.5;
    final date = _DateHeading(today: today, compact: compact);
    final overview = _DailyOverview(
      open: open,
      done: done,
      focus: focus,
      onOpenFocus: onOpenFocus,
    );
    final habits = this.habits;
    final habitTile = habits == null
        ? null
        : ListenableBuilder(
            listenable: habits,
            builder: (context, _) {
              final list = [
                for (final habit in habits.visible)
                  if (!habit.archived) habit,
              ];
              if (list.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: _HabitsTile(
                  controller: habits,
                  habits: list,
                  onOpen: onOpenHabits,
                ),
              );
            },
          );

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.gutter - 2,
        Space.sm,
        Space.gutter - 2,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) ...[
            date,
            const SizedBox(height: Space.sm),
            overview,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: date),
                const SizedBox(width: Space.lg),
                Expanded(child: overview),
              ],
            ),
          ?habitTile,
        ],
      ),
    );
  }
}

class _DateHeading extends StatelessWidget {
  const _DateHeading({required this.today, required this.compact});

  final DateTime today;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final settings = CalendarScope.of(context);
    final parts = formatDate(
      today,
      settings,
      today: today,
      alwaysYear: true,
    ).split(' ');
    final weekday = weekdayNames[today.weekday - 1];

    return Semantics(
      label: '$weekday ${parts.join(' ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.xs,
          Space.sm,
          Space.xs,
          Space.sm,
        ),
        child: Row(
          children: [
            Text(
              parts.first,
              style: theme.textTheme.displayLarge?.copyWith(
                color: colors.primary,
                fontSize: compact ? 56 : 72,
                height: 1,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekday,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    parts.skip(1).join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single glanceable surface replaces competing task and focus cards.
class _DailyOverview extends StatelessWidget {
  const _DailyOverview({
    required this.open,
    required this.done,
    this.focus,
    this.onOpenFocus,
  });

  final int open;
  final int? done;
  final FocusController? focus;
  final VoidCallback? onOpenFocus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final focus = this.focus;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaled = MediaQuery.textScalerOf(context).scale(1);
          final column = constraints.maxWidth < 330 || scaled >= 1.4;
          final tasks = _TasksOverview(open: open, done: done);
          if (focus == null) return tasks;
          final shortcut = _FocusShortcut(
            controller: focus,
            onOpen: onOpenFocus,
          );
          if (column) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tasks,
                const SizedBox(height: Space.sm),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: Space.sm),
                shortcut,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: tasks),
              const SizedBox(width: Space.md),
              shortcut,
            ],
          );
        },
      ),
    );
  }
}

class _TasksOverview extends StatelessWidget {
  const _TasksOverview({required this.open, required this.done});

  final int open;
  final int? done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = (done ?? 0) + open;
    final fraction = done == null || total == 0 ? null : done! / total;
    final value = done == null
        ? '${persianDigits(open)} باز'
        : '${persianDigits(done)} از ${persianDigits(total)}';

    return Semantics(
      label: done == null
          ? '${persianDigits(open)} کار باز برای امروز'
          : '${persianDigits(done)} کار از ${persianDigits(total)} کار امروز انجام شد',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'کارهای امروز',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          if (fraction != null) ...[
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 4,
                color: colors.primary,
                backgroundColor: colors.outlineVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small and reachable; navigation, not a second primary action.
class _FocusShortcut extends StatelessWidget {
  const _FocusShortcut({required this.controller, this.onOpen});

  final FocusController controller;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final seconds = (controller.remaining.inMilliseconds / 1000).ceil();
        final clock = persianDigits(
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
        );
        final running = controller.running;
        return Semantics(
          button: true,
          label: running
              ? 'تمرکز در جریان، $clock مانده؛ باز کردن تمرکز'
              : 'باز کردن تمرکز',
          excludeSemantics: true,
          child: Material(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.md,
                    Space.sm,
                    Space.sm,
                    Space.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 20,
                        color: colors.onPrimaryContainer,
                      ),
                      const SizedBox(width: Space.sm),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تمرکز',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                          Text(
                            clock,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: Space.sm),
                      Icon(
                        Icons.chevron_left_rounded,
                        color: colors.onPrimaryContainer,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Today's habits, each ticked in place as in Loop; a measurable habit
/// opens the habits screen instead.
class _HabitsTile extends StatelessWidget {
  const _HabitsTile({
    required this.controller,
    required this.habits,
    this.onOpen,
  });

  final HabitsController controller;
  final List<Habit> habits;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = controller.today;
    final done = habits.where((h) => controller.stats(h).counts(today)).length;
    final shown = habits.take(5).toList();
    return SoftTile(
      onTap: onOpen,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      child: Row(
        children: [
          Semantics(
            label:
                'عادت‌های امروز: ${persianDigits(done)} از ${persianDigits(habits.length)}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _Caption('عادت‌ها'),
                Text(
                  '${persianDigits(done)} از ${persianDigits(habits.length)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final h in shown)
                      _HabitCheck(
                        habit: h,
                        done: controller.stats(h).counts(today),
                        onTap: h.isNumeric
                            ? onOpen
                            : () => controller.toggle(h, today),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitCheck extends StatelessWidget {
  const _HabitCheck({required this.habit, required this.done, this.onTap});
  final Habit habit;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = habitColor(context, habit.color);
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      button: true,
      checked: done,
      label: habit.name,
      excludeSemantics: true,
      child: Tooltip(
        message: habit.name,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: done ? color : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color, width: 2),
                ),
                child: done
                    ? Icon(Icons.check_rounded, size: 20, color: ink)
                    : Center(
                        child: Text(
                          habit.name.characters.first,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
