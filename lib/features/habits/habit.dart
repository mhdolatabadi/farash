import 'package:flutter/material.dart';
import 'package:farash/core/text/persian_digits.dart';

enum HabitKind { boolean, numeric }

enum HabitTarget { atLeast, atMost }

/// Days counted from 1970-01-01, so that day arithmetic ignores DST.
int epochDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

/// The local calendar day for [day], at midnight.
DateTime dayDate(int day) {
  final utc = DateTime.fromMillisecondsSinceEpoch(
    day * Duration.millisecondsPerDay,
    isUtc: true,
  );
  return DateTime(utc.year, utc.month, utc.day);
}

/// "2026-10-22", the form the API stores.
String dayKey(int day) {
  final d = dayDate(day);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

int parseDayKey(String key) => epochDay(DateTime.parse(key));

/// One recorded day. A day without an entry is unknown.
class HabitEntry {
  const HabitEntry({required this.value, this.skip = false});

  HabitEntry.fromJson(Map<String, dynamic> j)
    : value = (j['value'] as num).toDouble(),
      skip = j['skip'] == true;

  /// 1 or 0 for a yes/no habit; the amount for a measurable one.
  final double value;
  final bool skip;
}

/// The twenty habit colours of Loop Habit Tracker, for light and dark themes.
const habitColorsLight = [
  Color(0xFFD32F2F), Color(0xFFE64A19), Color(0xFFF57C00), Color(0xFFFF8F00), //
  Color(0xFFF9A825), Color(0xFFAFB42B), Color(0xFF7CB342), Color(0xFF388E3C),
  Color(0xFF00897B), Color(0xFF00ACC1), Color(0xFF039BE5), Color(0xFF1976D2),
  Color(0xFF303F9F), Color(0xFF5E35B1), Color(0xFF8E24AA), Color(0xFFD81B60),
  Color(0xFF5D4037), Color(0xFF303030), Color(0xFF757575), Color(0xFF9E9E9E),
];

const habitColorsDark = [
  Color(0xFFEF9A9A), Color(0xFFFFAB91), Color(0xFFFFCC80), Color(0xFFFFE082), //
  Color(0xFFFFF59D), Color(0xFFE6EE9C), Color(0xFFC5E1A5), Color(0xFFA5D6A7),
  Color(0xFF80CBC4), Color(0xFF80DEEA), Color(0xFF81D4FA), Color(0xFF90CAF9),
  Color(0xFF9FA8DA), Color(0xFFB39DDB), Color(0xFFCE93D8), Color(0xFFF48FB1),
  Color(0xFFBCAAA4), Color(0xFFF5F5F5), Color(0xFFE0E0E0), Color(0xFFBDBDBD),
];

Color habitColor(BuildContext context, int index) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (dark ? habitColorsDark : habitColorsLight)[index.clamp(0, 19)];
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    this.question = '',
    this.notes = '',
    this.color = 8,
    this.kind = HabitKind.boolean,
    this.freqNum = 1,
    this.freqDen = 1,
    this.target = HabitTarget.atLeast,
    this.targetValue = 0,
    this.unit = '',
    this.sortOrder = 0,
    this.archived = false,
    this.entries = const {},
  });

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
    id: j['id'] as String,
    name: j['name'] as String,
    question: j['question'] as String? ?? '',
    notes: j['notes'] as String? ?? '',
    color: j['color'] as int? ?? 8,
    kind: j['kind'] == 'numeric' ? HabitKind.numeric : HabitKind.boolean,
    freqNum: j['freq_num'] as int? ?? 1,
    freqDen: j['freq_den'] as int? ?? 1,
    target: j['target_type'] == 'at_most'
        ? HabitTarget.atMost
        : HabitTarget.atLeast,
    targetValue: (j['target_value'] as num? ?? 0).toDouble(),
    unit: j['unit'] as String? ?? '',
    sortOrder: j['sort_order'] as int? ?? 0,
    archived: j['archived'] == true,
    entries: {
      for (final e in (j['entries'] as List? ?? const []))
        parseDayKey((e as Map<String, dynamic>)['day'] as String):
            HabitEntry.fromJson(e),
    },
  );

  final String id, name, question, notes, unit;
  final int color, freqNum, freqDen, sortOrder;
  final HabitKind kind;
  final HabitTarget target;
  final double targetValue;
  final bool archived;

  /// Recorded days, keyed by [epochDay].
  final Map<int, HabitEntry> entries;

  bool get isNumeric => kind == HabitKind.numeric;
  bool get isDaily => freqNum == 1 && freqDen == 1;

  Habit copyWith({
    String? name,
    int? color,
    int? sortOrder,
    bool? archived,
    Map<int, HabitEntry>? entries,
  }) => Habit(
    id: id,
    name: name ?? this.name,
    question: question,
    notes: notes,
    color: color ?? this.color,
    kind: kind,
    freqNum: freqNum,
    freqDen: freqDen,
    target: target,
    targetValue: targetValue,
    unit: unit,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
    entries: entries ?? this.entries,
  );

  /// Loop's frequency labels: «هر روز», «۳ بار در هفته», «هر ۵ روز».
  String get frequencyLabel {
    if (isNumeric) {
      return switch (freqDen) {
        1 => 'در روز',
        7 => 'در هفته',
        30 => 'در ماه',
        _ => persianDigits('در $freqDen روز'),
      };
    }
    if (freqNum == freqDen) return 'هر روز';
    if (freqNum == 1 && freqDen == 7) return 'هر هفته';
    if (freqNum == 1) return persianDigits('هر $freqDen روز');
    if (freqDen == 7) return persianDigits('$freqNum بار در هفته');
    if (freqDen == 30 || freqDen == 31) {
      return persianDigits('$freqNum بار در ماه');
    }
    return persianDigits('$freqNum بار در $freqDen روز');
  }

  /// «دست‌کم ۸ لیوان در روز».
  String get targetLabel {
    final amount = '${formatAmount(targetValue)} $unit'.trim();
    final bound = target == HabitTarget.atLeast ? 'دست‌کم' : 'حداکثر';
    return '$bound $amount $frequencyLabel';
  }
}

/// "۲٫۵", without trailing zeros.
String formatAmount(double value) {
  var text = value.toStringAsFixed(value.abs() >= 100 ? 0 : 2);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return persianDigits(text.replaceAll('.', '٫'));
}

/// Fields for a new habit, or the fields to change on an existing one.
class HabitDraft {
  const HabitDraft({
    this.name,
    this.question,
    this.notes,
    this.color,
    this.kind,
    this.freqNum,
    this.freqDen,
    this.target,
    this.targetValue,
    this.unit,
    this.archived,
  });

  final String? name, question, notes, unit;
  final int? color, freqNum, freqDen;
  final HabitKind? kind;
  final HabitTarget? target;
  final double? targetValue;
  final bool? archived;

  Map<String, Object?> toJson() => {
    'name': ?name,
    'question': ?question,
    'notes': ?notes,
    'color': ?color,
    if (kind != null) 'kind': kind!.name,
    'freq_num': ?freqNum,
    'freq_den': ?freqDen,
    if (target != null)
      'target_type': target == HabitTarget.atMost ? 'at_most' : 'at_least',
    'target_value': ?targetValue,
    'unit': ?unit,
    'archived': ?archived,
  };
}
