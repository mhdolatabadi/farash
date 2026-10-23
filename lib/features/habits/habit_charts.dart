import 'dart:math';

import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_stats.dart';

enum Bucket { day, week, month, quarter, year }

const bucketLabels = {
  Bucket.day: 'روز',
  Bucket.week: 'هفته',
  Bucket.month: 'ماه',
  Bucket.quarter: 'فصل',
  Bucket.year: 'سال',
};

/// A span of days for one chart column, inclusive.
class Period {
  const Period(this.start, this.end, this.label);
  final int start, end;
  final String label;
}

/// Month number since year 0 in the chosen calendar.
int _monthIndex(int day, CalendarSettings s) {
  final d = dayDate(day);
  if (s.isJalali) {
    final j = JalaliDate.fromGregorian(d);
    return j.year * 12 + j.month - 1;
  }
  return d.year * 12 + d.month - 1;
}

int _monthStart(int index, CalendarSettings s) {
  final year = index ~/ 12, month = index % 12 + 1;
  return epochDay(
    s.isJalali
        ? JalaliDate(year, month, 1).toGregorian()
        : DateTime(year, month, 1),
  );
}

int bucketStart(Bucket b, int day, CalendarSettings s) => switch (b) {
  Bucket.day => day,
  Bucket.week => day - (dayDate(day).weekday - s.weekStart + 7) % 7,
  Bucket.month => _monthStart(_monthIndex(day, s), s),
  Bucket.quarter => _monthStart(
    _monthIndex(day, s) - _monthIndex(day, s) % 3,
    s,
  ),
  Bucket.year => _monthStart(_monthIndex(day, s) - _monthIndex(day, s) % 12, s),
};

String _label(Bucket b, int start, CalendarSettings s) {
  final index = _monthIndex(start, s);
  final months = s.isJalali ? jalaliMonths : gregorianMonths;
  return persianDigits(switch (b) {
    Bucket.day || Bucket.week =>
      '${s.isJalali ? JalaliDate.fromGregorian(dayDate(start)).day : dayDate(start).day}',
    Bucket.month => months[index % 12],
    Bucket.quarter => 'فصل ${index % 12 ~/ 3 + 1}',
    Bucket.year => '${index ~/ 12}',
  });
}

/// The last [count] periods through [today], oldest first.
List<Period> periods(Bucket b, int today, int count, CalendarSettings s) {
  final result = <Period>[];
  var end = today;
  for (var i = 0; i < count; i++) {
    final start = bucketStart(b, end, s);
    result.add(Period(start, end, _label(b, start, s)));
    end = start - 1;
  }
  return result.reversed.toList();
}

/// A horizontally scrollable chart drawn left to right in time, opening on
/// the newest column at the right edge, like the day columns of the list.
class TimeScroller extends StatelessWidget {
  const TimeScroller({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: SizedBox(width: max(width, constraints.maxWidth), child: child),
      ),
    ),
  );
}

TextPainter _text(String text, TextStyle? style, {TextAlign? align}) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      textAlign: align ?? TextAlign.center,
    )..layout();

/// Habit strength over time, as a line with a dot per period.
class ScoreChart extends StatelessWidget {
  const ScoreChart({
    super.key,
    required this.stats,
    required this.bucket,
    required this.settings,
    required this.color,
  });

  final HabitStats stats;
  final Bucket bucket;
  final CalendarSettings settings;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final list = periods(
      bucket,
      stats.today,
      periodsSince(bucket, stats.from, stats.today, settings, cap: 120),
      settings,
    );
    final points = [for (final p in list) stats.score(p.end)];
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      label: persianDigits(
        'نمودار قدرت؛ اکنون ${(stats.currentScore * 100).round()}٪',
      ),
      child: SizedBox(
        height: 200,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TimeScroller(
                  width: list.length * 36.0,
                  child: CustomPaint(
                    painter: _LinePainter(
                      list,
                      points,
                      color,
                      theme.colorScheme.outlineVariant,
                      labelStyle,
                    ),
                  ),
                ),
              ),
              // The percent axis stays put while the chart scrolls.
              CustomPaint(
                size: const Size(40, 200),
                painter: _AxisPainter(labelStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.periods, this.values, this.color, this.grid, this.style);

  final List<Period> periods;
  final List<double> values;
  final Color color, grid;
  final TextStyle? style;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 0.0, bottom = _axisBottom, top = _axisTop;
    final h = size.height - bottom - top;
    final step = (size.width - left) / periods.length;
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final pct in [0, 25, 50, 75, 100]) {
      final y = top + h * (1 - pct / 100);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
    }
    final path = Path();
    final dot = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final x = left + step * (i + .5);
      final y = top + h * (1 - values[i]);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      final x = left + step * (i + .5);
      canvas.drawCircle(Offset(x, top + h * (1 - values[i])), 3.5, dot);
      if (i % 2 == (values.length - 1) % 2) {
        final t = _text(periods[i].label, style);
        t.paint(canvas, Offset(x - t.width / 2, size.height - bottom + 6));
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.color != color || old.grid != grid;
}

const _axisBottom = 24.0, _axisTop = 12.0;

class _AxisPainter extends CustomPainter {
  _AxisPainter(this.style);

  final TextStyle? style;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height - _axisBottom - _axisTop;
    for (final pct in [0, 25, 50, 75, 100]) {
      final y = _axisTop + h * (1 - pct / 100);
      final t = _text(persianDigits('$pct٪'), style);
      t.paint(canvas, Offset(6, y - t.height / 2));
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) => old.style != style;
}

/// How many periods reach back to [from], at least 8 and at most [cap].
int periodsSince(
  Bucket b,
  int from,
  int today,
  CalendarSettings s, {
  int cap = 60,
}) {
  var count = 1;
  var start = bucketStart(b, today, s);
  while (start > from && count < cap) {
    start = bucketStart(b, start - 1, s);
    count++;
  }
  return max(8, count);
}

/// Repetitions (yes/no) or amounts (measurable) per period, as bars.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.stats,
    required this.bucket,
    required this.settings,
    required this.color,
  });

  final HabitStats stats;
  final Bucket bucket;
  final CalendarSettings settings;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final list = periods(
      bucket,
      stats.today,
      periodsSince(bucket, stats.from, stats.today, settings),
      settings,
    );
    final totals = [for (final p in list) stats.total(p.start, p.end)];
    final theme = Theme.of(context);
    return Semantics(
      label: 'نمودار تاریخچه',
      child: SizedBox(
        height: 200,
        child: TimeScroller(
          width: list.length * 36.0,
          child: CustomPaint(
            painter: _BarPainter(
              list,
              totals,
              color,
              theme.colorScheme.outlineVariant,
              theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.periods, this.totals, this.color, this.grid, this.style);

  final List<Period> periods;
  final List<double> totals;
  final Color color, grid;
  final TextStyle? style;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 24.0, top = 20.0;
    final h = size.height - bottom - top;
    final step = size.width / periods.length;
    final peak = totals.fold(0.0, max);
    canvas.drawLine(
      Offset(0, size.height - bottom),
      Offset(size.width, size.height - bottom),
      Paint()..color = grid,
    );
    final bar = Paint()..color = color;
    for (var i = 0; i < totals.length; i++) {
      final x = step * i + step / 2;
      final height = peak == 0 ? 0.0 : h * totals[i] / peak;
      if (height > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x - 8, size.height - bottom - height, 16, height),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          bar,
        );
        final value = _text(formatAmount(totals[i]), style);
        value.paint(
          canvas,
          Offset(x - value.width / 2, size.height - bottom - height - 16),
        );
      }
      final label = _text(periods[i].label, style);
      label.paint(
        canvas,
        Offset(x - label.width / 2, size.height - bottom + 6),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.totals != totals || old.color != color;
}

/// A heat map of weeks: one column per week, newest at the right, one row
/// per weekday. Tapping a day records it.
class HabitCalendar extends StatelessWidget {
  const HabitCalendar({
    super.key,
    required this.stats,
    required this.settings,
    required this.color,
    required this.onDay,
    this.weeks = 26,
  });

  final HabitStats stats;
  final CalendarSettings settings;
  final Color color;
  final ValueChanged<int> onDay;
  final int weeks;

  static const _cell = 28.0, _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final firstWeek =
        bucketStart(Bucket.week, stats.today, settings) - (weeks - 1) * 7;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(color: muted);
    Widget day(int d) {
      if (d > stats.today) return const SizedBox.square(dimension: _cell);
      final check = stats.check(d);
      final habit = stats.habit;
      double strength = switch (check) {
        DayCheck.yes => 1,
        DayCheck.auto => .45,
        DayCheck.skip => .25,
        _ => 0,
      };
      if (habit.isNumeric && check == DayCheck.yes) {
        final daily = habit.targetValue / habit.freqDen;
        strength = daily <= 0
            ? 1
            : habit.target == HabitTarget.atMost
            ? (stats.counts(d) ? 1 : .35)
            : (stats.value(d) / daily).clamp(.2, 1.0);
      }
      final date = dayDate(d);
      final fill = strength == 0
          ? theme.colorScheme.surfaceContainerHighest
          : color.withValues(alpha: strength);
      final number = settings.isJalali
          ? JalaliDate.fromGregorian(date).day
          : date.day;
      return Semantics(
        button: true,
        label:
            '${formatDate(date, settings, withWeekday: true)}: ${switch (check) {
              DayCheck.yes => habit.isNumeric ? '${formatAmount(stats.value(d))} ${habit.unit}' : 'انجام شد',
              DayCheck.auto => 'در بازهٔ انجام‌شده',
              DayCheck.skip => 'رد شد',
              DayCheck.no => 'انجام نشد',
              DayCheck.unknown => 'ثبت نشده',
            }}',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onDay(d),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: _cell,
            height: _cell,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
              border: d == stats.today
                  ? Border.all(color: theme.colorScheme.onSurface, width: 1.5)
                  : null,
            ),
            child: Text(
              persianDigits(number),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: strength >= .45
                    ? (ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black)
                    : muted,
              ),
            ),
          ),
        ),
      );
    }

    final months = settings.isJalali ? jalaliMonths : gregorianMonths;
    return TimeScroller(
      width: weeks * (_cell + _gap) + 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var w = 0; w < weeks; w++)
            Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: Column(
                children: [
                  SizedBox(
                    height: 18,
                    width: _cell,
                    child: OverflowBox(
                      maxWidth: 80,
                      alignment: Alignment.centerLeft,
                      child: () {
                        final start = firstWeek + w * 7;
                        final index = _monthIndex(start + 6, settings);
                        final starts =
                            w == 0 || _monthIndex(start - 1, settings) != index;
                        return starts
                            ? Text(months[index % 12], style: labelStyle)
                            : const SizedBox();
                      }(),
                    ),
                  ),
                  for (var i = 0; i < 7; i++) ...[
                    day(firstWeek + w * 7 + i),
                    if (i < 6) const SizedBox(height: _gap),
                  ],
                ],
              ),
            ),
          Column(
            children: [
              const SizedBox(height: 18),
              for (var i = 0; i < 7; i++)
                SizedBox(
                  height: _cell + (i < 6 ? _gap : 0),
                  width: 32,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: _cell,
                      child: Center(
                        child: Text(
                          weekdayInitials[(settings.weekStart - 1 + i) % 7],
                          style: labelStyle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Loop's frequency chart: how often the habit was done on each weekday,
/// per month, as dots sized by count.
class FrequencyChart extends StatelessWidget {
  const FrequencyChart({
    super.key,
    required this.stats,
    required this.settings,
    required this.color,
    this.months = 12,
  });

  final HabitStats stats;
  final CalendarSettings settings;
  final Color color;
  final int months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = periods(Bucket.month, stats.today, months, settings);
    final counts = [
      for (final p in list)
        List.generate(7, (i) {
          var n = 0;
          for (var d = p.start; d <= p.end; d++) {
            final row = (dayDate(d).weekday - settings.weekStart + 7) % 7;
            if (row == i && stats.check(d) == DayCheck.yes) n++;
          }
          return n;
        }),
    ];
    final peak = max(1, counts.expand((c) => c).fold(0, max));
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    const cell = 30.0;
    return Semantics(
      label: 'نمودار تکرار در روزهای هفته',
      child: TimeScroller(
        width: months * cell + 36,
        child: Row(
          children: [
            for (final (m, column) in counts.indexed)
              Column(
                children: [
                  for (final n in column)
                    SizedBox.square(
                      dimension: cell,
                      child: Center(
                        child: Container(
                          width: n == 0 ? 4 : 8 + 16 * n / peak,
                          height: n == 0 ? 4 : 8 + 16 * n / peak,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: n == 0
                                ? theme.colorScheme.outlineVariant
                                : color,
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: cell,
                    height: 20,
                    child: OverflowBox(
                      maxWidth: 60,
                      child: Text(
                        list[m].label,
                        style: labelStyle?.copyWith(fontSize: 9),
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            Column(
              children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: 32,
                    height: cell,
                    child: Center(
                      child: Text(
                        weekdayInitials[(settings.weekStart - 1 + i) % 7],
                        style: labelStyle,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The longest streaks as bars, from first to last day.
class StreakList extends StatelessWidget {
  const StreakList({
    super.key,
    required this.stats,
    required this.settings,
    required this.color,
  });

  final HabitStats stats;
  final CalendarSettings settings;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final best = stats.best(8);
    if (best.isEmpty) {
      return Text(
        'هنوز زنجیره‌ای ثبت نشده است.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final longest = best.first.length;
    final current = stats.currentStreak;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final today = dayDate(stats.today);
    return Column(
      children: [
        for (final s in best)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Semantics(
              label: persianDigits(
                '${s.length} روز، از ${formatDate(dayDate(s.start), settings, today: today)} تا ${formatDate(dayDate(s.end), settings, today: today)}',
              ),
              excludeSemantics: true,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        formatDate(dayDate(s.start), settings, today: today),
                        style: style,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => Center(
                          child: Container(
                            height: 24,
                            width: max(32.0, c.maxWidth * s.length / longest),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  identical(s, current) ||
                                      (current != null && current.end == s.end)
                                  ? color
                                  : color.withValues(alpha: .55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              persianDigits(s.length),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color:
                                    ThemeData.estimateBrightnessForColor(
                                          color,
                                        ) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: Text(
                        formatDate(dayDate(s.end), settings, today: today),
                        style: style,
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
