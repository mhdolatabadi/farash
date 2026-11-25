import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/habits/habit.dart';
import 'package:menval/features/habits/habits_controller.dart';

/// A daybook heading and compact ledger strip: actual tasks lead the page.
/// Keeps the previous API while replacing the equal-weight bento tiles.
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
    final largeText = scale >= 1.5;
    final narrow = MediaQuery.sizeOf(context).width < 600 || largeText;
    final heading = _LedgerDate(today: today, compact: narrow);
    final summary = _DayStatus(
      open: open,
      done: done,
      focus: focus,
      onOpenFocus: onOpenFocus,
    );
    final habits = this.habits;
    final habitStrip = habits == null
        ? null
        : ListenableBuilder(
            listenable: habits,
            builder: (context, _) {
              final list = [
                for (final h in habits.visible)
                  if (!h.archived) h,
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
        Space.gutter,
        Space.sm,
        Space.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (narrow) ...[
            heading,
            const SizedBox(height: Space.md),
            summary,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: heading),
                const SizedBox(width: Space.xl),
                Expanded(child: summary),
              ],
            ),
          ?habitStrip,
        ],
      ),
    );
  }
}

class _LedgerDate extends StatelessWidget {
  const _LedgerDate({required this.today, required this.compact});

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              parts.first,
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: compact ? 64 : 76,
                height: 1,
                fontWeight: FontWeight.w900,
                color: colors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    weekday,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    parts.skip(1).join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
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

/// A quiet strip, not two competing dashboard cards.
class _DayStatus extends StatelessWidget {
  const _DayStatus({
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final vertical = constraints.maxWidth < 320 || scale >= 1.5;
            final progress = _WorkProgress(open: open, done: done);
            final shortcut = focus == null
                ? null
                : _FocusShortcut(controller: focus, onOpen: onOpenFocus);
            if (shortcut == null) return progress;
            if (vertical) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  progress,
                  const SizedBox(height: Space.sm),
                  shortcut,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: progress),
                const SizedBox(width: Space.md),
                shortcut,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkProgress extends StatelessWidget {
  const _WorkProgress({required this.open, required this.done});
  final int open;
  final int? done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final total = (done ?? 0) + open;
    final progress = done == null || total == 0 ? null : done! / total;
    final value = done == null
        ? '${persianDigits(open)} باز'
        : '${persianDigits(done!)} از ${persianDigits(total)}';
    return Semantics(
      label: done == null
          ? '${persianDigits(open)} کار باز برای امروز'
          : '${persianDigits(done!)} کار از ${persianDigits(total)} کار امروز انجام شد',
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
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
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
            borderRadius: BorderRadius.circular(12),
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
                      const SizedBox(width: Space.xs),
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
                              fontWeight: FontWeight.w800,
                              color: colors.onPrimaryContainer,
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
                        size: 22,
                        color: colors.onPrimaryContainer,
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

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
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
