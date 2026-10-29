import 'package:flutter/material.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habits_controller.dart';

/// The tiles above «امروز»: the date, the day's tasks, the focus timer and
/// today's habits. A tile whose data is missing is left out, never filled
/// with a guess.
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

  /// Open tasks due today or late.
  final int open;

  /// Tasks the server counted as completed today; null while unknown.
  final int? done;

  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final tasks = _TasksTile(open: open, done: done);
    final focus = this.focus;
    final focusTile = focus == null
        ? null
        : _FocusTile(controller: focus, onOpen: onOpenFocus);
    final habits = this.habits;
    final habitsTile = habits == null
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
    // Large text stacks the tiles; otherwise the date takes the height of
    // the two tiles beside it.
    final stacked = scale >= 1.5;
    final date = _DateTile(today: today, tall: !stacked);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter - 2,
        Space.sm,
        Space.gutter - 2,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked) ...[
            date,
            const SizedBox(height: Space.md),
            tasks,
            if (focusTile != null) ...[
              const SizedBox(height: Space.md),
              focusTile,
            ],
          ] else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: date),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tasks,
                        if (focusTile != null) ...[
                          const SizedBox(height: Space.md),
                          focusTile,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ?habitsTile,
        ],
      ),
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

class _DateTile extends StatelessWidget {
  const _DateTile({required this.today, required this.tall});
  final DateTime today;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = CalendarScope.of(context);
    // "۶ آبان ۱۴۰۵": the day alone, then month and year.
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
      child: SoftTile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Caption(weekday),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                parts.first,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: tall ? 76 : 56,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Text(
              parts.skip(1).join(' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TasksTile extends StatelessWidget {
  const _TasksTile({required this.open, required this.done});
  final int open;
  final int? done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = this.done;
    final total = (done ?? 0) + open;
    final value = done == null || total == 0 ? null : done / total;
    final text = done == null
        ? '${persianDigits(open)} باز'
        : '${persianDigits(done)} از ${persianDigits(total)}';
    return Semantics(
      label: done == null
          ? '${persianDigits(open)} کار باز برای امروز'
          : '${persianDigits(done)} کار از ${persianDigits(total)} کار امروز انجام شد',
      excludeSemantics: true,
      child: SoftTile(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            if (value != null) ...[
              _Ring(value: value),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Caption('کارها'),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      text,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
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

class _Ring extends StatelessWidget {
  const _Ring({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 40,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 6,
        strokeCap: StrokeCap.round,
        color: colors.primary,
        backgroundColor: colors.outlineVariant,
      ),
    );
  }
}

/// The running or ready timer; opens Focus.
class _FocusTile extends StatelessWidget {
  const _FocusTile({required this.controller, this.onOpen});
  final FocusController controller;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          child: SoftTile(
            onTap: onOpen,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _Caption('تمرکز'),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          clock,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: running
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: running
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
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
