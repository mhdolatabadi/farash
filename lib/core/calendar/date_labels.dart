import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/core/text/persian_digits.dart';

const jalaliMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', //
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

const gregorianMonths = [
  'ژانویه', 'فوریه', 'مارس', 'آوریل', 'مه', 'ژوئن', //
  'ژوئیه', 'اوت', 'سپتامبر', 'اکتبر', 'نوامبر', 'دسامبر',
];

/// Indexed by DateTime.weekday - 1 (Monday first).
const weekdayNames = [
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه',
];

/// One-letter weekday headers for a month grid, same order.
const weekdayInitials = ['د', 'س', 'چ', 'پ', 'ج', 'ش', 'ی'];

DateTime dayOf(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Whole days from [from] to [to], ignoring time and DST.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// "۱۲ مهر", with the year when it is not [today]'s year.
String formatDate(
  DateTime date,
  CalendarSettings settings, {
  DateTime? today,
  bool withWeekday = false,
  bool alwaysYear = false,
}) {
  final now = today ?? DateTime.now();
  final String day;
  final String month;
  final int year;
  final int currentYear;
  if (settings.isJalali) {
    final j = JalaliDate.fromGregorian(date);
    day = '${j.day}';
    month = jalaliMonths[j.month - 1];
    year = j.year;
    currentYear = JalaliDate.fromGregorian(now).year;
  } else {
    day = '${date.day}';
    month = gregorianMonths[date.month - 1];
    year = date.year;
    currentYear = now.year;
  }
  final weekday = withWeekday ? '${weekdayNames[date.weekday - 1]} ' : '';
  final suffix = alwaysYear || year != currentYear ? ' $year' : '';
  return persianDigits('$weekday$day $month$suffix');
}

/// امروز / فردا / دیروز, the weekday within the coming week, or the date.
String relativeDay(
  DateTime date,
  CalendarSettings settings, {
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final offset = daysBetween(now, date);
  return switch (offset) {
    0 => 'امروز',
    1 => 'فردا',
    -1 => 'دیروز',
    > 1 && < 7 => weekdayNames[date.weekday - 1],
    _ => formatDate(date, settings, today: now),
  };
}

/// "۱۴:۰۵".
String formatTime(DateTime moment) => persianDigits(
  '${moment.hour.toString().padLeft(2, '0')}:'
  '${moment.minute.toString().padLeft(2, '0')}',
);

/// "۱ ساعت و ۳۰ دقیقه".
String formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final parts = [
    if (hours > 0) '$hours ساعت',
    if (rest > 0 || hours == 0) '$rest دقیقه',
  ];
  return persianDigits(parts.join(' و '));
}

/// The first day of the week containing [date].
DateTime startOfWeek(DateTime date, int weekStart) =>
    dayOf(date).subtract(Duration(days: (date.weekday - weekStart + 7) % 7));
