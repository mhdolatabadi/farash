import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_detail.dart';
import 'package:farash/features/habits/habit_editor.dart';
import 'package:farash/features/habits/habit_stats.dart';
import 'package:farash/features/habits/habits_controller.dart';

/// Width of one day column; also its touch target.
const habitCellWidth = 48.0;
const _rowHeight = 60.0;
const _maxWidth = 760.0;

/// Loop Habit Tracker's main screen: every habit with its strength ring and
/// a checkmark grid of the most recent days, today first.
class HabitsView extends StatefulWidget {
  const HabitsView({super.key, required this.controller});

  final HabitsController controller;

  @override
  State<HabitsView> createState() => _HabitsViewState();
}

class _HabitsViewState extends State<HabitsView> {
  HabitsController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.message.addListener(_showMessage);
    if (_c.all.isEmpty && !_c.loading) _c.load();
  }

  @override
  void didUpdateWidget(HabitsView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.message.removeListener(_showMessage);
      _c.message.addListener(_showMessage);
    }
  }

  @override
  void dispose() {
    _c.message.removeListener(_showMessage);
    super.dispose();
  }

  void _showMessage() {
    final text = _c.message.value;
    if (text == null || !mounted) return;
    _c.message.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final habit = await createHabit(context, _c);
    if (habit != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('«${habit.name}» اضافه شد.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, CalendarScope.of(context)]),
      builder: (context, _) {
        final habits = _c.visible;
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = min(constraints.maxWidth, _maxWidth);
            final inset = (constraints.maxWidth - width) / 2;
            // Name and ring keep at least 150, so a two-word name stays on
            // one line; the rest, less the end gutter, becomes day columns.
            // Rows and the day header grow with the user's text size.
            final scaler = MediaQuery.textScalerOf(context);
            final rowHeight = max(_rowHeight, scaler.scale(16) * 2.6 + 12);
            final headerHeight = max(48.0, scaler.scale(12) * 3.2 + 8);
            final columns = ((width - Space.sm - 150) / habitCellWidth)
                .floor()
                .clamp(1, 7);
            final list = CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  title: const Text('عادت‌ها'),
                  actions: [_FilterMenu(controller: _c)],
                ),
                if (habits.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      height: headerHeight,
                      today: _c.today,
                      columns: columns,
                      inset: inset,
                      settings: CalendarScope.of(context),
                      theme: Theme.of(context),
                    ),
                  ),
                if (_c.loading && _c.all.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_c.error != null && _c.all.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      icon: Icons.cloud_off_rounded,
                      text: 'عادت‌ها بارگذاری نشدند.',
                      action: TextButton(
                        onPressed: _c.load,
                        child: const Text('دوباره'),
                      ),
                    ),
                  )
                else if (habits.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(
                      icon: Icons.check_box_outlined,
                      text: _c.all.isEmpty
                          ? 'هنوز عادتی نساخته‌اید.'
                          : 'عادت فعالی ندارید.',
                      action: FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('عادت تازه'),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 0, inset, 96),
                    sliver: SliverReorderableList(
                      itemCount: habits.length,
                      onReorderItem: (from, to) {
                        final habit = habits[from];
                        final shown = [...habits]..removeAt(from);
                        final rest = [..._c.all]..remove(habit);
                        // Map the visible slot onto the full manual order,
                        // which may hold hidden archived habits.
                        final index = to < shown.length
                            ? rest.indexOf(shown[to])
                            : rest.indexOf(shown.last) + 1;
                        _c.reorder(habit, index);
                      },
                      itemBuilder: (context, i) {
                        final habit = habits[i];
                        final row = HabitRow(
                          key: ValueKey(habit.id),
                          habit: habit,
                          stats: _c.stats(habit),
                          columns: columns,
                          height: rowHeight,
                          controller: _c,
                        );
                        return _c.sort == HabitSort.manual
                            ? ReorderableDelayedDragStartListener(
                                key: ValueKey(habit.id),
                                index: i,
                                child: row,
                              )
                            : KeyedSubtree(key: ValueKey(habit.id), child: row);
                      },
                    ),
                  ),
              ],
            );
            // One primary action, as in Loop: a FAB that never covers the
            // last row thanks to the list's bottom padding.
            return Stack(
              children: [
                list,
                if (_c.all.isNotEmpty)
                  PositionedDirectional(
                    end: 16 + inset,
                    bottom: 16,
                    child: FloatingActionButton(
                      tooltip: 'عادت تازه',
                      onPressed: _add,
                      child: const Icon(Icons.add_rounded),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, required this.action});

  final IconData icon;
  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({required this.controller});

  final HabitsController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PopupMenuButton<Object>(
      tooltip: 'نمایش و ترتیب',
      icon: const Icon(Icons.filter_list_rounded),
      onSelected: (value) {
        if (value == 'archived') {
          c.showArchived = !c.showArchived;
        } else if (value is HabitSort) {
          c.sort = value;
        }
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        c.notifyListeners();
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'archived',
          checked: c.showArchived,
          child: const Text('نمایش بایگانی‌شده‌ها'),
        ),
        const PopupMenuDivider(),
        for (final (sort, label) in [
          (HabitSort.manual, 'ترتیب دستی'),
          (HabitSort.name, 'بر اساس نام'),
          (HabitSort.color, 'بر اساس رنگ'),
          (HabitSort.score, 'بر اساس قدرت'),
        ])
          CheckedPopupMenuItem(
            value: sort,
            checked: c.sort == sort,
            child: Text(label),
          ),
      ],
    );
  }
}

/// Weekday initial and day of month above each day column.
class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader({
    required this.height,
    required this.today,
    required this.columns,
    required this.inset,
    required this.settings,
    required this.theme,
  });

  final int today, columns;
  final double inset, height;
  final CalendarSettings settings;
  final ThemeData theme;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Row(
        children: [
          const Spacer(),
          for (var i = 0; i < columns; i++)
            SizedBox(
              width: habitCellWidth,
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      habitWeekdays[dayDate(today - i).weekday - 1],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i == 0 ? theme.colorScheme.onSurface : muted,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      persianDigits(dayOfMonth(today - i, settings)),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: i == 0 ? theme.colorScheme.onSurface : muted,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: Space.sm),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeader old) =>
      old.today != today ||
      old.height != height ||
      old.columns != columns ||
      old.inset != inset ||
      old.theme != theme ||
      old.settings.system != settings.system;
}

/// Short weekday names for the day columns, indexed by weekday − 1.
const habitWeekdays = ['دو', 'سه', 'چهار', 'پنج', 'جمعه', 'شنبه', 'یک'];

int dayOfMonth(int day, CalendarSettings settings) {
  final date = dayDate(day);
  return settings.isJalali ? JalaliDate.fromGregorian(date).day : date.day;
}

class HabitRow extends StatelessWidget {
  const HabitRow({
    super.key,
    required this.habit,
    required this.stats,
    required this.columns,
    required this.controller,
    this.height = _rowHeight,
  });

  final Habit habit;
  final HabitStats stats;
  final int columns;
  final double height;
  final HabitsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = habitColor(context, habit.color);
    final settings = CalendarScope.of(context);
    // Flat rows separated by hairlines, as in Loop.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => HabitDetailScreen(
                        controller: controller,
                        habitId: habit.id,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: Space.gutter,
                      end: Space.sm,
                    ),
                    child: Row(
                      children: [
                        Semantics(
                          label: persianDigits(
                            'قدرت ${(stats.currentScore * 100).round()}٪',
                          ),
                          child: ScoreRing(
                            score: stats.currentScore,
                            color: color,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            habit.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: habit.archived
                                  ? theme.colorScheme.onSurfaceVariant
                                  : color,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (habit.archived)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 4),
                            child: Icon(
                              Icons.archive_outlined,
                              size: 18,
                              semanticLabel: 'بایگانی‌شده',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < columns; i++)
                CheckCell(
                  habit: habit,
                  stats: stats,
                  day: stats.today - i,
                  label: relativeDay(
                    dayDate(stats.today - i),
                    settings,
                    today: dayDate(stats.today),
                  ),
                  onTap: () =>
                      recordDay(context, controller, habit, stats.today - i),
                ),
              const SizedBox(width: Space.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// Toggles a yes/no day, or asks for a measurable day's amount.
Future<void> recordDay(
  BuildContext context,
  HabitsController controller,
  Habit habit,
  int day,
) async {
  if (!habit.isNumeric) {
    HapticFeedback.selectionClick();
    await controller.toggle(habit, day);
    return;
  }
  final current = (controller.byId(habit.id) ?? habit).entries[day];
  final result = await showDialog<_AmountResult>(
    context: context,
    builder: (_) => _AmountDialog(
      habit: habit,
      day: day,
      initial: current,
      settings: CalendarScope.of(context),
    ),
  );
  if (result == null) return;
  await controller.setEntry(habit, day, result.entry);
}

/// One day of one habit: a check, a cross, a skip mark or an amount.
class CheckCell extends StatelessWidget {
  const CheckCell({
    super.key,
    required this.habit,
    required this.stats,
    required this.day,
    required this.label,
    required this.onTap,
  });

  final Habit habit;
  final HabitStats stats;
  final int day;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = habitColor(context, habit.color);
    final muted = theme.colorScheme.onSurfaceVariant;
    final check = stats.check(day);
    final Widget mark;
    final String state;
    if (habit.isNumeric && check != DayCheck.skip) {
      final value = stats.value(day);
      final met = check == DayCheck.yes && stats.counts(day);
      state = check == DayCheck.yes
          ? '${formatAmount(value)} ${habit.unit}'.trim()
          : 'ثبت نشده';
      mark = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatAmount(value),
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: check == DayCheck.yes
                  ? (met ? color : color.withValues(alpha: .7))
                  : muted.withValues(alpha: .45),
              fontWeight: met ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          if (habit.unit.isNotEmpty)
            Text(
              habit.unit,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: theme.textTheme.labelSmall?.copyWith(
                color: check == DayCheck.yes
                    ? color.withValues(alpha: .8)
                    : muted.withValues(alpha: .45),
                fontSize: 10,
              ),
            ),
        ],
      );
    } else {
      final (icon, tint, text) = switch (check) {
        DayCheck.yes => (Icons.check_rounded, color, 'انجام شد'),
        DayCheck.auto => (
          Icons.check_rounded,
          color.withValues(alpha: .4),
          'در بازهٔ انجام‌شده',
        ),
        DayCheck.skip => (
          Icons.keyboard_double_arrow_left_rounded,
          color.withValues(alpha: .75),
          'رد شد',
        ),
        DayCheck.no => (
          Icons.close_rounded,
          muted.withValues(alpha: .7),
          'انجام نشد',
        ),
        DayCheck.unknown => (
          Icons.close_rounded,
          muted.withValues(alpha: .35),
          'ثبت نشده',
        ),
      };
      state = text;
      mark = Icon(
        icon,
        color: tint,
        size: switch (check) {
          DayCheck.yes || DayCheck.auto => 24,
          DayCheck.skip => 20,
          _ => 16,
        },
      );
    }
    return Semantics(
      button: true,
      label: '${habit.name}، $label: $state',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: habitCellWidth,
          height: double.infinity,
          child: Center(child: mark),
        ),
      ),
    );
  }
}

/// Loop's small strength indicator: a ring filled to the habit's score.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.score,
    required this.color,
    this.size = 22,
    this.stroke,
  });

  final double score, size;
  final double? stroke;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _RingPainter(
      score.clamp(0, 1),
      color,
      Theme.of(context).colorScheme.outlineVariant,
      stroke ?? size * .2,
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.score, this.color, this.track, this.stroke);

  final double score, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * pi, false, paint);
    if (score > 0) {
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * score,
        false,
        paint
          ..color = color
          ..strokeCap = score < 1 ? StrokeCap.round : StrokeCap.butt,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.score != score || old.color != color || old.track != track;
}

class _AmountResult {
  const _AmountResult(this.entry);
  final HabitEntry? entry;
}

/// Reads "۲٫۵", "2.5" or "2,5".
double? parseAmount(String text) {
  const persian = '۰۱۲۳۴۵۶۷۸۹', arabic = '٠١٢٣٤٥٦٧٨٩';
  final buffer = StringBuffer();
  for (final ch in text.trim().split('')) {
    final p = persian.indexOf(ch), a = arabic.indexOf(ch);
    buffer.write(
      p >= 0
          ? '$p'
          : a >= 0
          ? '$a'
          : (ch == '٫' || ch == ',' || ch == '،')
          ? '.'
          : ch,
    );
  }
  final value = double.tryParse(buffer.toString());
  return value == null || value.isNaN || value.isInfinite || value < 0
      ? null
      : value;
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.habit,
    required this.day,
    required this.initial,
    required this.settings,
  });

  final Habit habit;
  final int day;
  final HabitEntry? initial;
  final CalendarSettings settings;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _field = TextEditingController(
    text: widget.initial == null || widget.initial!.skip
        ? ''
        : formatAmount(widget.initial!.value),
  );
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final value = parseAmount(_field.text);
    if (value == null) {
      setState(() => _error = 'یک عدد وارد کنید.');
      return;
    }
    Navigator.pop(context, _AmountResult(HabitEntry(value: value)));
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    return AlertDialog(
      title: Text(habit.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDate(dayDate(widget.day), widget.settings, withWeekday: true),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: habit.question.isEmpty ? 'مقدار' : habit.question,
              suffixText: habit.unit.isEmpty ? null : habit.unit,
              errorText: _error,
              helperText: habit.targetLabel,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.initial != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _AmountResult(null)),
            child: const Text('پاک کردن'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _AmountResult(HabitEntry(value: 0, skip: true)),
          ),
          child: const Text('رد کردن'),
        ),
        FilledButton(onPressed: _save, child: const Text('ثبت')),
      ],
    );
  }
}
