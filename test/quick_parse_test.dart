import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';

void main() {
  // A Wednesday afternoon.
  final now = DateTime(2026, 10, 14, 15, 30);
  final today = DateTime(2026, 10, 14);
  DateTime plus(int days) => today.add(Duration(days: days));
  QuickTask parse(String text) => parseQuickTask(text, now: now);

  test('the issue example sets everything', () {
    final t = parse('جلسه با علی فردا ساعت ۵ عصر #کار @تلفن p1');
    expect(t.title, 'جلسه با علی');
    expect(t.day, plus(1));
    expect(t.hour, 17);
    expect(t.minute, 0);
    expect(t.project, 'کار');
    expect(t.labels, ['تلفن']);
    expect(t.priority, 1);
    expect(t.tokens.map((k) => k.kind), [
      QuickTokenKind.date,
      QuickTokenKind.time,
      QuickTokenKind.project,
      QuickTokenKind.label,
      QuickTokenKind.priority,
    ]);
  });

  test('relative days in Persian and English', () {
    expect(parse('خرید امروز').day, today);
    expect(parse('خرید پس‌فردا').day, plus(2));
    expect(parse('خرید پس فردا').day, plus(2));
    expect(parse('buy milk tomorrow').day, plus(1));
    expect(parse('گزارش هفته بعد').day, plus(7));
    expect(parse('report next week').day, plus(7));
    expect(parse('سفر ۳ روز دیگر').day, plus(3));
    expect(parse('trip in 3 days').day, plus(3));
    expect(parse('اجاره ماه بعد').day, DateTime(2026, 11, 14));
  });

  test('weekdays are the coming one; بعد and next add a week', () {
    // Today is Wednesday.
    expect(parse('کلاس شنبه').day, plus(3));
    expect(parse('کلاس سه شنبه').day, plus(6));
    expect(parse('کلاس سه‌شنبه').day, plus(6));
    expect(parse('کلاس چهارشنبه').day, plus(7));
    expect(parse('کلاس دوشنبه بعد').day, plus(12));
    expect(parse('class monday').day, plus(5));
    expect(parse('class next monday').day, plus(12));
  });

  test('Jalali and Gregorian dates roll into next year once passed', () {
    final mehr15 = JalaliDate(1405, 7, 15).toGregorian();
    expect(
      parse('تولد ۱۵ مهر').day!.isAfter(today) ||
          parse('تولد ۱۵ مهر').day == today,
      isTrue,
    );
    expect(
      parse('تولد ۱۵ مهر ۱۴۰۶').day,
      JalaliDate(1406, 7, 15).toGregorian(),
    );
    final farvardin = parse('عید ۱ فروردین').day!;
    expect(farvardin.isAfter(today), isTrue);
    expect(JalaliDate.fromGregorian(farvardin).month, 1);
    expect(mehr15.year, 2026);
    expect(parse('party 20 oct').day, DateTime(2026, 10, 20));
    expect(parse('party oct 1').day, DateTime(2027, 10, 1));
  });

  test('times, with a part of day or after ساعت / at', () {
    expect(parse('تماس ساعت ۱۷:۳۰').hour, 17);
    expect(parse('تماس ساعت ۱۷:۳۰').minute, 30);
    expect(parse('تماس ۸ صبح فردا').hour, 8);
    expect(parse('تماس ۸ صبح فردا').day, plus(1));
    expect(parse('ناهار ۱ ظهر').hour, 13);
    expect(parse('شام ۹ شب').hour, 21);
    expect(parse('call 5pm').hour, 17);
    expect(parse('call at 17').hour, 17);
    expect(parse('call 12am tomorrow').hour, 0);
  });

  test('a time with no date is today, or tomorrow once it has passed', () {
    expect(parse('call 5pm').day, today);
    expect(parse('call 9am').day, plus(1));
  });

  test('plain numbers and words stay in the title', () {
    final t = parse('خرید ۳ سیب و 5 apples');
    expect(t.title, 'خرید ۳ سیب و 5 apples');
    expect(t.day, isNull);
    expect(t.hour, isNull);
    expect(t.tokens, isEmpty);
    expect(parse('email a@b.com').labels, isEmpty);
  });

  test('priorities, labels, project and deadline', () {
    final t = parse('گزارش !!2 @کار @فوری {۲۰ مهر} #شرکت');
    expect(t.priority, 2);
    expect(t.labels, ['کار', 'فوری']);
    expect(t.project, 'شرکت');
    expect(JalaliDate.fromGregorian(t.deadline!).day, 20);
    expect(t.title, 'گزارش');
    expect(parse('report {tomorrow}').deadline, plus(1));
    expect(parse('x p5').priority, isNull);
  });

  test('a dismissed token stays part of the title', () {
    final first = parse('خواندن کتاب فردا');
    final date = first.tokens.single;
    final again = parseQuickTask(
      'خواندن کتاب فردا',
      now: now,
      ignore: {(date.start, date.end)},
    );
    expect(again.day, isNull);
    expect(again.title, 'خواندن کتاب فردا');
  });

  test('token ranges point into the original Persian text', () {
    const input = 'جلسه ساعت ۵ عصر';
    final time = parse(input).tokens.single;
    expect(input.substring(time.start, time.end), 'ساعت ۵ عصر');
  });
}
