import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/controls.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/app/press_depth.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/calendar/jalali.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/habits/habit.dart';
import 'package:menval/features/habits/habit_detail.dart';
import 'package:menval/features/habits/habit_editor.dart';
import 'package:menval/features/habits/habit_stats.dart';
import 'package:menval/features/habits/habits_controller.dart';

/// Width of one day column; also its touch target.
const habitCellWidth = 48.0;
const _rowHeight = 52.0;
const _maxWidth = 1160.0;

/// Compact habit history. Names remain visible while date columns scroll.
/// Each column is an actual local calendar day, with today first in RTL.
class HabitsView extends StatefulWidget {
  const HabitsView({
    super.key,
    required this.controller,
    this.onQuickAdd,
    this.embedded = false,
  });

  final HabitsController controller;
  final VoidCallback? onQuickAdd;

  /// The shared shell provides the title, navigation and creation FAB.
  final bool embedded;

  @override
  State<HabitsView> createState() => _HabitsViewState();
}

class _HabitsViewState extends State<HabitsView> {
  HabitsController get _c => widget.controller;
  double _historyOffset = 0;
  bool _syncingHistory = false;
  final _historyControllers = <String, ScrollController>{};

  ScrollController _historyController(String key) =>
      _historyControllers.putIfAbsent(key, () {
        final controller = ScrollController(
          initialScrollOffset: _historyOffset,
        );
        controller.addListener(() {
          if (_syncingHistory || !controller.hasClients) return;
          _syncingHistory = true;
          _historyOffset = controller.offset;
          for (final other in _historyControllers.values) {
            if (identical(other, controller) || !other.hasClients) continue;
            final offset = _historyOffset.clamp(
              other.position.minScrollExtent,
              other.position.maxScrollExtent,
            );
            if (other.offset != offset) other.jumpTo(offset);
          }
          _syncingHistory = false;
        });
        return controller;
      });

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
    for (final controller in _historyControllers.values) {
      controller.dispose();
    }
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
            final scaler = MediaQuery.textScalerOf(context);
            final rowHeight = max(_rowHeight, scaler.scale(14) * 2.4 + 12);
            final headerHeight = max(52.0, scaler.scale(12) * 3.2 + 8);
            final nameWidth = width >= 700 ? 180.0 : 120.0;
            // Recent dated history stays available at every screen width.
            // Scroll to older days without adding range controls to the page.
            const columns = 30;
            const cellWidth = habitCellWidth;
            final list = CustomScrollView(
              slivers: [
                if (!widget.embedded)
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: Soft.ground(context),
                    title: const Text('عادت‌ها'),
                    actions: [
                      if (widget.onQuickAdd != null)
                        IconButton(
                          tooltip: 'افزودن کار',
                          onPressed: widget.onQuickAdd,
                          icon: const Icon(Icons.add_task_rounded),
                        ),
                      _FilterMenu(controller: _c),
                    ],
                  ),
                if (widget.embedded && habits.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: inset + 16),
                    sliver: SliverToBoxAdapter(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: _FilterMenu(controller: _c),
                      ),
                    ),
                  ),
                if (habits.isNotEmpty)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      height: headerHeight,
                      today: _c.today,
                      columns: columns,
                      cellWidth: cellWidth,
                      inset: inset,
                      nameWidth: nameWidth,
                      controller: _historyController('header'),
                      settings: CalendarScope.of(context),
                      theme: Theme.of(context),
                      ground: Soft.ground(context),
                      action: widget.embedded ? _FilterMenu(controller: _c) : null,
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
                      action: widget.embedded
                          ? const SizedBox.shrink()
                          : FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('عادت تازه'),
                            ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset + 16, 0, inset + 16, 96),
                    // The rows sit in one well on the soft ground.
                    sliver: DecoratedSliver(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(Soft.tileRadius),
                      ),
                      sliver: SliverReorderableList(
                        itemCount: habits.length,
                        onReorderItem: (from, to) {
                          if (from == to) return;
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
                            cellWidth: cellWidth,
                            divider: false,
                            nameWidth: nameWidth,
                            historyController: _historyController(habit.id),
                          );
                          final pressed = Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              0,
                              4,
                              0,
                              4,
                            ),
                            child: PressDepth(
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                elevation: 2,
                                shadowColor: Theme.of(
                                  context,
                                ).colorScheme.shadow.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(12),
                                clipBehavior: Clip.antiAlias,
                                child: row,
                              ),
                            ),
                          );
                          return _c.sort == HabitSort.manual
                              ? ReorderableDelayedDragStartListener(
                                  key: ValueKey(habit.id),
                                  index: i,
                                  child: pressed,
                                )
                              : KeyedSubtree(
                                  key: ValueKey(habit.id),
                                  child: pressed,
                                );
                        },
                      ),
                    ),
                  ),
              ],
            );
            // One primary action, as in Loop: a FAB that never covers the
            // last row thanks to the list's bottom padding.
            return Stack(
              children: [
                if (widget.embedded)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Space.md,
                        Space.lg,
                        Space.md,
                        Space.lg,
                      ),
                      child: IgnorePointer(
                        child: SoftWell(
                          radius: 36,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  )
                else
                  Positioned.fill(
                    child: ColoredBox(color: Soft.ground(context)),
                  ),
                list,
                if (!widget.embedded && _c.all.isNotEmpty)
                  PositionedDirectional(
                    end: 16 + inset,
                    bottom: 16,
                    child: PressDepth(
                      borderRadius: BorderRadius.circular(18),
                      child: FloatingActionButton(
                        tooltip: 'عادت تازه',
                        onPressed: _add,
                        child: const Icon(Icons.add_rounded),
                      ),
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

/// A pinned label for each real day, scrolling in step with every habit row.
class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader({
    required this.height,
    required this.today,
    required this.columns,
    required this.cellWidth,
    required this.inset,
    required this.nameWidth,
    required this.controller,
    required this.settings,
    required this.theme,
    required this.ground,
    this.action,
  });

  final Color ground;
  final int today, columns;
  final double inset, height, cellWidth, nameWidth;
  final ScrollController controller;
  final CalendarSettings settings;
  final ThemeData theme;
  final Widget? action;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) => Container(
    height: height,
    color: ground,
    padding: EdgeInsets.symmetric(horizontal: inset + 16),
    child: Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('عادت', style: theme.textTheme.labelMedium),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('habit-history-header'),
            scrollDirection: Axis.horizontal,
            controller: controller,
            child: Row(
              children: [
                for (var i = 0; i < columns; i++)
                  SizedBox(
                    width: cellWidth,
                    child: ExcludeSemantics(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            habitWeekdays[dayDate(today - i).weekday - 1],
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            persianDigits(dayOfMonth(today - i, settings)),
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: i == 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  @override
  bool shouldRebuild(_DayHeader old) =>
      old.today != today ||
      old.height != height ||
      old.columns != columns ||
      old.cellWidth != cellWidth ||
      old.inset != inset ||
      old.theme != theme ||
      old.ground != ground ||
      old.nameWidth != nameWidth ||
      old.action != action ||
      old.settings.system != settings.system;
}

/// Short weekday names for the day columns, indexed by weekday − 1.
const habitWeekdays = ['دو', 'سه', 'چهار', 'پنج', 'جمعه', 'شنبه', 'یک'];

// RTL calendar rows run from Saturday to Friday, matching the approved view.
int saturdayOf(int day) =>
    day - ((dayDate(day).weekday + 1) % DateTime.daysPerWeek);

IconData habitGlyph(String name) {
  if (name.contains('مطالع') || name.contains('کتاب')) {
    return Icons.menu_book_outlined;
  }
  if (name.contains('ورزش') || name.contains('تمرین')) {
    return Icons.fitness_center_rounded;
  }
  if (name.contains('نوشت') || name.contains('یادداشت')) {
    return Icons.edit_outlined;
  }
  if (name.contains('پیاده') || name.contains('قدم')) {
    return Icons.directions_walk_outlined;
  }
  return Icons.check_circle_outline_rounded;
}

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
    this.cellWidth = habitCellWidth,
    this.height = _rowHeight,
    this.divider = true,
    this.nameWidth = 120,
    this.historyController,
  });

  /// The hairline under the row; off for the last row of the well.
  final bool divider;
  final Habit habit;
  final HabitStats stats;
  final int columns;
  final double height, cellWidth, nameWidth;
  final ScrollController? historyController;
  final HabitsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;
    final settings = CalendarScope.of(context);
    // Raised compact rows sit inside a single lower surface.
    return DecoratedBox(
      decoration: const BoxDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              SizedBox(
                width: nameWidth,
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
                      start: Space.sm,
                      end: Space.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(habitGlyph(habit.name), color: color, size: 20),
                        const SizedBox(width: Space.xs),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                habit.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: habit.archived
                                      ? theme.colorScheme.onSurfaceVariant
                                      : color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    persianDigits(
                                      '${stats.currentStreak?.length ?? 0}',
                                    ),
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 10,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.local_fire_department_outlined,
                                    size: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey('habit-history-${habit.id}'),
                  scrollDirection: Axis.horizontal,
                  controller: historyController,
                  child: Row(
                    children: [
                      for (var i = 0; i < columns; i++)
                        SizedBox(
                          height: height,
                          child: CheckCell(
                            key: ValueKey(
                              '${habit.id}-${dayKey(stats.today - i)}',
                            ),
                            habit: habit,
                            stats: stats,
                            width: cellWidth,
                            day: stats.today - i,
                            label: relativeDay(
                              dayDate(stats.today - i),
                              settings,
                              today: dayDate(stats.today),
                            ),
                            onTap: () => recordDay(
                              context,
                              controller,
                              habit,
                              stats.today - i,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
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
    this.width = habitCellWidth,
  });

  final Habit habit;
  final HabitStats stats;
  final int day;
  final String label;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.brightness == Brightness.dark
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
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
      final (icon, text) = switch (check) {
        DayCheck.yes => (null, 'انجام شد'),
        DayCheck.auto => (null, 'در بازهٔ انجام‌شده'),
        DayCheck.skip => (Icons.keyboard_double_arrow_left_rounded, 'رد شد'),
        DayCheck.no => (Icons.close_rounded, 'انجام نشد'),
        DayCheck.unknown => (null, 'ثبت نشده'),
      };
      return SizedBox(
        width: width,
        child: Center(
          child: MenvalCheckbox(
            value: check == DayCheck.yes || check == DayCheck.auto,
            label: '${habit.name}، $label: $text',
            activeColor: check == DayCheck.auto ? muted : null,
            indeterminateIcon: icon,
            onChanged: (_) => onTap(),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${habit.name}، $label: $state',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
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
