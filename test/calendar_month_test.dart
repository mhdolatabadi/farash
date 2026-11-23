import 'package:farash/core/calendar/calendar_month.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jalali Farvardin starts on Nowruz and grid uses Saturday', () {
    final settings = CalendarSettings();
    final first = JalaliDate(1405, 1, 1).toGregorian();
    final month = monthContaining(first, settings);
    expect(month.firstDay, first);
    expect(month.lastDay, JalaliDate(1405, 1, 31).toGregorian());
    expect(month.gridStart.weekday, DateTime.saturday);
    expect(month.gridEnd.weekday, DateTime.friday);
    expect(month.days.length % 7, 0);
  });

  test('Esfand rollover advances to Farvardin', () {
    final settings = CalendarSettings();
    final esfand = JalaliDate(1404, 12, 1).toGregorian();
    expect(
      JalaliDate.fromGregorian(shiftCalendarMonth(esfand, 1, settings)),
      const JalaliDate(1405, 1, 1),
    );
    expect(
      JalaliDate.fromGregorian(shiftCalendarMonth(esfand, -1, settings)),
      const JalaliDate(1404, 11, 1),
    );
  });

  test('Jalali leap Esfand has 30 days', () {
    final settings = CalendarSettings();
    final leapYear = [
      for (var year = 1400; year < 1420; year++)
        if (JalaliDate.isLeapYear(year)) year,
    ].first;
    final month = monthContaining(
      JalaliDate(leapYear, 12, 1).toGregorian(),
      settings,
    );
    expect(daysBetween(month.firstDay, month.lastDay) + 1, 30);
  });

  test('Gregorian calendar and Monday week start', () {
    final settings = CalendarSettings(
      system: CalendarSystem.gregorian,
      weekStart: DateTime.monday,
    );
    final month = monthContaining(DateTime(2026, 2, 17), settings);
    expect(month.firstDay, DateTime(2026, 2, 1));
    expect(month.lastDay, DateTime(2026, 2, 28));
    expect(month.gridStart.weekday, DateTime.monday);
    expect(month.gridEnd.weekday, DateTime.sunday);
    expect(month.days.length % 7, 0);
    expect(shiftCalendarMonth(DateTime(2026, 12, 31), 1, settings),
        DateTime(2027, 1, 1));
  });
}
