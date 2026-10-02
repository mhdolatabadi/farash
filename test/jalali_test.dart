import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';

void main() {
  test('known days convert both ways', () {
    final pairs = {
      DateTime(2024, 3, 20): const JalaliDate(1403, 1, 1),
      DateTime(2025, 3, 20): const JalaliDate(1403, 12, 30),
      DateTime(2025, 3, 21): const JalaliDate(1404, 1, 1),
      DateTime(2026, 3, 21): const JalaliDate(1405, 1, 1),
      DateTime(2026, 9, 23): const JalaliDate(1405, 7, 1),
      DateTime(2026, 10, 1): const JalaliDate(1405, 7, 9),
      DateTime(1979, 2, 11): const JalaliDate(1357, 11, 22),
      DateTime(2000, 1, 1): const JalaliDate(1378, 10, 11),
    };
    pairs.forEach((gregorian, jalali) {
      expect(JalaliDate.fromGregorian(gregorian), jalali, reason: '$gregorian');
      expect(jalali.toGregorian(), gregorian, reason: '$jalali');
    });
  });

  test('every day of a long span round-trips and stays in order', () {
    var day = DateTime(1990);
    var previous = JalaliDate.fromGregorian(
      day.subtract(const Duration(days: 1)),
    );
    for (var i = 0; i < 365 * 60; i++) {
      final j = JalaliDate.fromGregorian(day);
      expect(j.toGregorian(), day);
      final expectedNext =
          previous.day < JalaliDate.monthLength(previous.year, previous.month)
          ? JalaliDate(previous.year, previous.month, previous.day + 1)
          : previous.month < 12
          ? JalaliDate(previous.year, previous.month + 1, 1)
          : JalaliDate(previous.year + 1, 1, 1);
      expect(j, expectedNext);
      previous = j;
      day = DateTime(day.year, day.month, day.day + 1);
    }
  });

  test('leap years and month lengths', () {
    expect(JalaliDate.isLeapYear(1403), isTrue);
    expect(JalaliDate.isLeapYear(1404), isFalse);
    expect(JalaliDate.monthLength(1404, 1), 31);
    expect(JalaliDate.monthLength(1404, 7), 30);
    expect(JalaliDate.monthLength(1404, 12), 29);
    expect(JalaliDate.monthLength(1403, 12), 30);
  });

  group('labels', () {
    final jalali = CalendarSettings();
    final gregorian = CalendarSettings(system: CalendarSystem.gregorian);
    final today = DateTime(2026, 10, 1); // Thursday, 9 Mehr 1405

    test('dates read in Persian with Persian digits', () {
      expect(formatDate(DateTime(2026, 10, 3), jalali, today: today), '۱۱ مهر');
      expect(
        formatDate(DateTime(2027, 4, 1), jalali, today: today),
        '۱۲ فروردین ۱۴۰۶',
      );
      expect(
        formatDate(
          DateTime(2026, 10, 3),
          jalali,
          today: today,
          withWeekday: true,
        ),
        'شنبه ۱۱ مهر',
      );
      expect(
        formatDate(DateTime(2026, 10, 3), gregorian, today: today),
        '۳ اکتبر',
      );
    });

    test('relative days', () {
      expect(relativeDay(today, jalali, today: today), 'امروز');
      expect(relativeDay(DateTime(2026, 10, 2), jalali, today: today), 'فردا');
      expect(relativeDay(DateTime(2026, 9, 30), jalali, today: today), 'دیروز');
      expect(
        relativeDay(DateTime(2026, 10, 4), jalali, today: today),
        'یکشنبه',
      );
      expect(
        relativeDay(DateTime(2026, 10, 20), jalali, today: today),
        '۲۸ مهر',
      );
    });

    test('times, durations and week starts', () {
      expect(formatTime(DateTime(2026, 1, 1, 9, 5)), '۰۹:۰۵');
      expect(formatDuration(30), '۳۰ دقیقه');
      expect(formatDuration(90), '۱ ساعت و ۳۰ دقیقه');
      expect(formatDuration(120), '۲ ساعت');
      expect(startOfWeek(today, DateTime.saturday), DateTime(2026, 9, 26));
      expect(startOfWeek(today, DateTime.monday), DateTime(2026, 9, 28));
      expect(
        startOfWeek(DateTime(2026, 9, 26), DateTime.saturday),
        DateTime(2026, 9, 26),
      );
    });
  });

  test('calendar settings persist per device', () async {
    final store = MemoryCalendarSettingsStore();
    final settings = CalendarSettings(store: store);
    expect(settings.isJalali, isTrue);
    expect(settings.weekStart, DateTime.saturday);
    await settings.setSystem(CalendarSystem.gregorian);
    await settings.setWeekStart(DateTime.monday);

    final reloaded = CalendarSettings(store: store);
    await reloaded.load();
    expect(reloaded.isJalali, isFalse);
    expect(reloaded.weekStart, DateTime.monday);
  });
}
