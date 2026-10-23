import 'dart:math';

import 'package:farash/features/habits/habit.dart';

/// What a day shows, following Loop Habit Tracker's entry values.
enum DayCheck {
  /// Nothing recorded.
  unknown,

  /// Recorded as not done.
  no,

  /// Not recorded, but covered by a non-daily habit's completed interval.
  auto,

  /// Recorded as done.
  yes,

  /// Recorded as skipped: neither counts nor breaks a streak.
  skip,
}

class Streak {
  const Streak(this.start, this.end);

  /// Epoch days, inclusive.
  final int start, end;
  int get length => end - start + 1;
}

/// A habit's derived history from its first recorded day through today:
/// Loop's automatic checkmarks, habit strength and streaks.
class HabitStats {
  HabitStats._(
    this.habit,
    this.from,
    this.today,
    this.checks,
    this.scores,
    this.streaks,
  );

  factory HabitStats.of(Habit habit, int today) {
    final days = habit.entries.keys.where((d) => d <= today);
    final from = days.isEmpty ? today : days.reduce(min);
    final checks = _checks(habit, from, today);
    return HabitStats._(
      habit,
      from,
      today,
      checks,
      _scores(habit, from, checks),
      _streaks(habit, from, checks),
    );
  }

  final Habit habit;

  /// Epoch days covered: [from] through [today].
  final int from, today;

  /// Indexed by day − [from].
  final List<DayCheck> checks;
  final List<double> scores;

  /// Oldest first.
  final List<Streak> streaks;

  DayCheck check(int day) =>
      day < from || day > today ? DayCheck.unknown : checks[day - from];

  /// The amount recorded on [day]; 0 when nothing or a skip was recorded.
  double value(int day) {
    final e = habit.entries[day];
    return e == null || e.skip ? 0 : e.value;
  }

  /// Habit strength, 0 to 1, at the end of [day].
  double score(int day) {
    if (day < from) {
      return habit.isNumeric && habit.target == HabitTarget.atMost ? 1 : 0;
    }
    return scores[min(day, today) - from];
  }

  double get currentScore => score(today);

  Streak? get currentStreak {
    if (streaks.isEmpty) return null;
    final last = streaks.last;
    // Today may still be pending, so a streak through yesterday is current.
    return last.end >= today - 1 ? last : null;
  }

  /// The longest streaks, longest first, ties broken by recency.
  List<Streak> best(int count) {
    final sorted = [...streaks]
      ..sort((a, b) {
        final byLength = b.length.compareTo(a.length);
        return byLength != 0 ? byLength : b.end.compareTo(a.end);
      });
    return sorted.take(count).toList();
  }

  /// Days recorded done (yes/no) or the sum of amounts (measurable).
  double total(int start, int end) {
    var sum = 0.0;
    for (var d = max(start, from); d <= min(end, today); d++) {
      if (habit.isNumeric) {
        sum += value(d);
      } else if (checks[d - from] == DayCheck.yes) {
        sum += 1;
      }
    }
    return sum;
  }

  /// Whether [day] counts toward a streak.
  bool counts(int day) => _counts(habit, check(day), value(day));
}

bool _counts(Habit habit, DayCheck check, double value) {
  if (check == DayCheck.skip || check == DayCheck.auto) return true;
  if (!habit.isNumeric) return check == DayCheck.yes;
  if (check != DayCheck.yes) return false;
  if (habit.target == HabitTarget.atMost) return value <= habit.targetValue;
  // A daily target must be met that day; longer targets count any progress.
  return habit.freqDen == 1 ? value >= habit.targetValue : value > 0;
}

/// Recorded values, plus Loop's automatic checkmarks: for a habit done
/// N times per D days, each run of N check-ins within D days marks the
/// whole interval as done.
List<DayCheck> _checks(Habit habit, int from, int today) {
  final checks = List.filled(today - from + 1, DayCheck.unknown);
  if (!habit.isNumeric && !habit.isDaily) {
    for (final (begin, end) in _intervals(habit)) {
      for (var d = max(begin, from); d <= min(end, today); d++) {
        checks[d - from] = DayCheck.auto;
      }
    }
  }
  for (final MapEntry(key: day, value: e) in habit.entries.entries) {
    if (day < from || day > today) continue;
    final i = day - from;
    if (e.skip) {
      checks[i] = DayCheck.skip;
    } else if (habit.isNumeric || e.value > 0) {
      checks[i] = DayCheck.yes;
    } else {
      // Unlike Loop, an explicit "not done" stays visible inside a
      // completed interval, so a tap always shows its result.
      checks[i] = DayCheck.no;
    }
  }
  return checks;
}

/// Loop's `buildIntervals` and `snapIntervalsTogether`, oldest first.
List<(int, int)> _intervals(Habit habit) {
  final yes = [
    for (final MapEntry(key: day, value: e) in habit.entries.entries)
      if (!e.skip && e.value > 0) day,
  ]..sort((a, b) => b.compareTo(a)); // newest first
  final num = habit.freqNum, den = habit.freqDen;
  final intervals = <(int, int, int)>[]; // begin, center, end
  for (var i = num - 1; i < yes.length; i++) {
    final begin = yes[i], center = yes[i - num + 1];
    if (center - begin < den) intervals.add((begin, center, begin + den - 1));
  }
  final ordered = intervals.reversed.toList();
  for (var i = 1; i < ordered.length; i++) {
    final (begin, center, end) = ordered[i];
    final gap = begin - ordered[i - 1].$3 - 1;
    if (gap <= 0 || end - gap < center) continue;
    ordered[i] = (begin - gap, center, end - gap);
  }
  return [for (final (b, _, e) in ordered) (b, e)];
}

/// Loop's exponential score: each day moves the score toward that day's
/// completion by a factor that depends on how often the habit is due.
double scoreStep(double frequency, double previous, double completed) {
  final multiplier = pow(0.5, sqrt(frequency) / 13.0).toDouble();
  return previous * multiplier + completed * (1 - multiplier);
}

List<double> _scores(Habit habit, int from, List<DayCheck> checks) {
  var num = habit.freqNum, den = habit.freqDen;
  final frequency = num / den;
  // Doubling smooths irregular schedules, such as a weekly habit done on
  // different weekdays.
  if (!habit.isNumeric && frequency < 1) {
    num *= 2;
    den *= 2;
  }
  final atMost = habit.isNumeric && habit.target == HabitTarget.atMost;
  final target = habit.targetValue;
  double amount(int i) {
    if (habit.isNumeric) {
      final e = habit.entries[from + i];
      return e == null || e.skip ? 0 : e.value;
    }
    return checks[i] == DayCheck.yes ? 1 : 0;
  }

  final scores = List.filled(checks.length, 0.0);
  var previous = atMost ? 1.0 : 0.0;
  var rolling = 0.0;
  for (var i = 0; i < checks.length; i++) {
    rolling += amount(i);
    if (i - den >= 0) rolling -= amount(i - den);
    if (checks[i] != DayCheck.skip) {
      final double completed;
      if (!habit.isNumeric) {
        completed = min(1.0, rolling / num);
      } else if (!atMost) {
        completed = target > 0 ? min(1.0, rolling / target) : 1.0;
      } else if (target > 0) {
        completed = (1 - (rolling - target) / target).clamp(0.0, 1.0);
      } else {
        completed = rolling > 0 ? 0.0 : 1.0;
      }
      previous = scoreStep(frequency, previous, completed);
    }
    scores[i] = previous;
  }
  return scores;
}

List<Streak> _streaks(Habit habit, int from, List<DayCheck> checks) {
  final streaks = <Streak>[];
  int? start;
  for (var i = 0; i < checks.length; i++) {
    final e = habit.entries[from + i];
    final counts = _counts(habit, checks[i], e == null || e.skip ? 0 : e.value);
    if (counts) {
      start ??= from + i;
    } else if (start != null) {
      streaks.add(Streak(start, from + i - 1));
      start = null;
    }
  }
  if (start != null) streaks.add(Streak(start, from + checks.length - 1));
  return streaks;
}
