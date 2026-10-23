import 'package:farash/core/calendar/jalali.dart';

/// Only the bounded quick-add grammar; the server validates the full rule.
class QuickRecurrence {
  const QuickRecurrence({
    required this.frequency,
    this.interval = 1,
    this.basis = 'due',
    this.weekday,
    this.monthDay,
  });

  final String frequency, basis;
  final int interval;

  /// ISO weekday (Monday 1 through Sunday 7).
  final int? weekday;
  final int? monthDay;

  bool accepts(DateTime day, String calendar) {
    if (weekday != null && day.weekday != weekday) return false;
    if (monthDay == null) return true;
    final j = JalaliDate.fromGregorian(day);
    final actualDay = calendar == 'jalali' ? j.day : day.day;
    final length = calendar == 'jalali'
        ? JalaliDate.monthLength(j.year, j.month)
        : DateTime(day.year, day.month + 1, 0).day;
    return actualDay == (monthDay! > length ? length : monthDay);
  }

  DateTime firstDay(DateTime from, String calendar) {
    for (var i = 0; i < 370; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      if (accepts(day, calendar)) return day;
    }
    throw StateError('No matching recurrence day');
  }

  Map<String, Object?> schedule({
    required String start,
    required String timezone,
    required String calendar,
    String? wallTime,
  }) => {
    'start': start,
    'timezone': timezone,
    'time': ?wallTime,
    'rule': {
      'frequency': frequency,
      'interval': interval,
      'calendar': calendar,
      'basis': basis,
      if (weekday != null) 'weekdays': [weekday! % 7],
      'month_day': ?monthDay,
    },
  };
}
