import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_stats.dart';

const today = 20000;

Habit habit({
  int num = 1,
  int den = 1,
  HabitKind kind = HabitKind.boolean,
  HabitTarget target = HabitTarget.atLeast,
  double targetValue = 0,
  Map<int, HabitEntry> entries = const {},
}) => Habit(
  id: 'h',
  name: 'h',
  freqNum: num,
  freqDen: den,
  kind: kind,
  target: target,
  targetValue: targetValue,
  entries: entries,
);

Map<int, HabitEntry> yes(Iterable<int> days) => {
  for (final d in days) d: const HabitEntry(value: 1),
};

void main() {
  test('days round-trip through the API key', () {
    final day = epochDay(DateTime(2026, 10, 22));
    expect(dayKey(day), '2026-10-22');
    expect(parseDayKey('2026-10-22'), day);
    expect(dayDate(day), DateTime(2026, 10, 22));
  });

  test('score step matches Loop', () {
    // Loop: 1 − 0.5^(1/13) for a first daily check.
    expect(scoreStep(1, 0, 1), closeTo(0.051922, 1e-6));
    expect(scoreStep(1, 1, 1), 1);
    expect(scoreStep(1 / 7, 0, 1), closeTo(0.019951, 1e-6));
  });

  test('daily habit: strength, streaks and totals', () {
    final h = habit(entries: yes([for (var d = today - 9; d <= today; d++) d]));
    final s = HabitStats.of(h, today);
    var expected = 0.0;
    for (var i = 0; i < 10; i++) {
      expected = scoreStep(1, expected, 1);
    }
    expect(s.currentScore, closeTo(expected, 1e-9));
    expect(s.streaks.single.length, 10);
    expect(s.currentStreak!.length, 10);
    expect(s.total(today - 100, today), 10);
    expect(s.score(today - 100), 0);
  });

  test('a recorded no breaks the streak; a skip keeps it and the score', () {
    final h = habit(
      entries: {
        ...yes([today - 4, today - 3, today - 1, today]),
        today - 2: const HabitEntry(value: 0, skip: true),
      },
    );
    final s = HabitStats.of(h, today);
    expect(s.check(today - 2), DayCheck.skip);
    expect(s.streaks.single.length, 5);
    expect(s.score(today - 2), s.score(today - 3));

    final broken = HabitStats.of(
      habit(
        entries: {
          ...yes([today - 4, today - 3, today - 1, today]),
          today - 2: const HabitEntry(value: 0),
        },
      ),
      today,
    );
    expect(broken.check(today - 2), DayCheck.no);
    expect(broken.streaks.map((s) => s.length), [2, 2]);
    expect(broken.best(1).single.end, today);
  });

  test('today pending keeps yesterday\'s streak current', () {
    final s = HabitStats.of(habit(entries: yes([today - 2, today - 1])), today);
    expect(s.currentStreak!.length, 2);
    final old = HabitStats.of(habit(entries: yes([today - 3])), today);
    expect(old.currentStreak, isNull);
  });

  test('weekly habits get automatic checks across the interval', () {
    // 3 times per week, done on three days within a week.
    final h = habit(
      num: 3,
      den: 7,
      entries: yes([today - 6, today - 4, today - 2]),
    );
    final s = HabitStats.of(h, today);
    for (var d = today - 6; d <= today; d++) {
      final expected = {today - 6, today - 4, today - 2}.contains(d)
          ? DayCheck.yes
          : DayCheck.auto;
      expect(s.check(d), expected, reason: 'day ${d - today}');
    }
    expect(s.streaks.single.length, 7);
    // Only real check-ins count toward totals.
    expect(s.total(today - 6, today), 3);
  });

  test('too few check-ins leave the interval unchecked', () {
    final s = HabitStats.of(
      habit(num: 3, den: 7, entries: yes([today - 6, today - 2])),
      today,
    );
    expect(s.check(today - 5), DayCheck.unknown);
    expect(s.streaks.length, 2);
  });

  test('a recorded no inside a completed interval stays visible', () {
    final s = HabitStats.of(
      habit(
        num: 1,
        den: 7,
        entries: {
          ...yes([today - 6]),
          today - 3: const HabitEntry(value: 0),
        },
      ),
      today,
    );
    expect(s.check(today - 3), DayCheck.no);
    expect(s.check(today - 4), DayCheck.auto);
  });

  test('measurable at-least habit scores by the share of its target', () {
    final h = habit(
      kind: HabitKind.numeric,
      targetValue: 8,
      entries: {
        today - 1: const HabitEntry(value: 8),
        today: const HabitEntry(value: 4),
      },
    );
    final s = HabitStats.of(h, today);
    final first = scoreStep(1, 0, 1);
    expect(s.score(today - 1), closeTo(first, 1e-9));
    expect(s.currentScore, closeTo(scoreStep(1, first, .5), 1e-9));
    expect(s.counts(today - 1), isTrue);
    expect(s.counts(today), isFalse);
    expect(s.total(today - 1, today), 12);
  });

  test('measurable at-most habit starts strong and drops when exceeded', () {
    final h = habit(
      kind: HabitKind.numeric,
      target: HabitTarget.atMost,
      targetValue: 2,
      entries: {
        today - 1: const HabitEntry(value: 1),
        today: const HabitEntry(value: 4),
      },
    );
    final s = HabitStats.of(h, today);
    expect(s.score(today - 1), 1);
    expect(s.currentScore, closeTo(scoreStep(1, 1, 0), 1e-9));
    expect(s.counts(today - 1), isTrue);
    expect(s.counts(today), isFalse);
  });

  test('labels follow Loop\'s frequency names', () {
    expect(habit().frequencyLabel, 'هر روز');
    expect(habit(num: 1, den: 7).frequencyLabel, 'هر هفته');
    expect(habit(num: 3, den: 7).frequencyLabel, '۳ بار در هفته');
    expect(habit(num: 1, den: 3).frequencyLabel, 'هر ۳ روز');
    expect(habit(num: 4, den: 30).frequencyLabel, '۴ بار در ماه');
    expect(
      Habit(
        id: 'w',
        name: 'آب',
        kind: HabitKind.numeric,
        targetValue: 2.5,
        unit: 'لیتر',
      ).targetLabel,
      'دست‌کم ۲٫۵ لیتر در روز',
    );
  });
}
