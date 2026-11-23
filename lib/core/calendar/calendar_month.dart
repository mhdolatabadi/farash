import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';

/// Inclusive calendar-month bounds, independent of external providers.
class CalendarMonth {
  const CalendarMonth({
    required this.firstDay,
    required this.lastDay,
    required this.gridStart,
    required this.gridEnd,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime gridStart;
  final DateTime gridEnd;

  /// Calendar cells in whole local days; never add 24-hour durations across DST.
  List<DateTime> get days => [
    for (var i = 0; i <= daysBetween(gridStart, gridEnd); i++)
      DateTime(gridStart.year, gridStart.month, gridStart.day + i),
  ];
}

CalendarMonth monthContaining(DateTime day, CalendarSettings settings) {
  final DateTime first;
  final DateTime next;
  if (settings.isJalali) {
    final j = JalaliDate.fromGregorian(day);
    first = JalaliDate(j.year, j.month, 1).toGregorian();
    next = j.month == 12
        ? JalaliDate(j.year + 1, 1, 1).toGregorian()
        : JalaliDate(j.year, j.month + 1, 1).toGregorian();
  } else {
    first = DateTime(day.year, day.month, 1);
    next = DateTime(day.year, day.month + 1, 1);
  }
  final last = DateTime(next.year, next.month, next.day - 1);
  final gridStart = startOfWeek(first, settings.weekStart);
  final gridEnd = DateTime(
    next.year,
    next.month,
    next.day + (settings.weekStart - next.weekday + 6) % 7 - 1,
  );
  return CalendarMonth(
    firstDay: first,
    lastDay: last,
    gridStart: gridStart,
    gridEnd: gridEnd,
  );
}

/// Shift calendar months without assuming that a Jalali month is Gregorian.
DateTime shiftCalendarMonth(
  DateTime day,
  int offset,
  CalendarSettings settings,
) {
  if (!settings.isJalali) {
    return DateTime(day.year, day.month + offset, 1);
  }
  final j = JalaliDate.fromGregorian(day);
  final monthIndex = j.year * 12 + j.month - 1 + offset;
  final year = (monthIndex / 12).floor();
  final month = monthIndex - year * 12 + 1;
  return JalaliDate(year, month, 1).toGregorian();
}
