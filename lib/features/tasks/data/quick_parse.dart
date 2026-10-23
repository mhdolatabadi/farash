import 'package:farash/core/calendar/jalali.dart';
import 'quick_recurrence.dart';
export 'quick_recurrence.dart';

/// What a recognised piece of quick-add text means.
enum QuickTokenKind {
  date,
  time,
  priority,
  project,
  label,
  deadline,
  section,
  recurrence,
}

/// A recognised piece of the text, by its character range in the input.
class QuickToken {
  const QuickToken(this.kind, this.start, this.end, this.text);

  final QuickTokenKind kind;
  final int start;
  final int end;

  /// The text as typed.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is QuickToken && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The task a line of quick-add text describes. Times are device-local.
class QuickTask {
  const QuickTask({
    required this.title,
    this.day,
    this.hour,
    this.minute = 0,
    this.deadline,
    this.priority,
    this.project,
    this.section,
    this.recurrence,
    this.labels = const [],
    this.tokens = const [],
  });

  /// The text with every recognised token taken out.
  final String title;

  /// The due day at local midnight, if a date or a time was given.
  final DateTime? day;

  /// 0–23 when a time of day was given.
  final int? hour;
  final int minute;
  final DateTime? deadline;

  /// 1 (most urgent) to 4.
  final int? priority;

  /// A project name after `#`.
  final String? project;
  final String? section;
  final QuickRecurrence? recurrence;

  /// Label names after `@`, without the `@`.
  final List<String> labels;
  final List<QuickToken> tokens;

  bool get hasTime => hour != null;
}

const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// Persian and Arabic digits become Latin; the length stays the same, so
/// ranges found in the result hold for the original.
String latinDigits(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final p = _persianDigits.indexOf(char);
    final a = _arabicDigits.indexOf(char);
    out.write(p >= 0 ? '$p' : (a >= 0 ? '$a' : char));
  }
  return out.toString();
}

const _jalaliMonths = {
  'فروردین': 1,
  'اردیبهشت': 2,
  'خرداد': 3,
  'تیر': 4,
  'مرداد': 5,
  'شهریور': 6,
  'مهر': 7,
  'آبان': 8,
  'آذر': 9,
  'دی': 10,
  'بهمن': 11,
  'اسفند': 12,
};

const _gregorianMonths = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

/// DateTime.weekday for each name.
const _weekdays = {
  'شنبه': DateTime.saturday,
  'یکشنبه': DateTime.sunday,
  'یک‌شنبه': DateTime.sunday,
  'دوشنبه': DateTime.monday,
  'سه‌شنبه': DateTime.tuesday,
  'سهشنبه': DateTime.tuesday,
  'چهارشنبه': DateTime.wednesday,
  'پنجشنبه': DateTime.thursday,
  'پنج‌شنبه': DateTime.thursday,
  'جمعه': DateTime.friday,
  'monday': DateTime.monday,
  'mon': DateTime.monday,
  'tuesday': DateTime.tuesday,
  'tue': DateTime.tuesday,
  'wednesday': DateTime.wednesday,
  'wed': DateTime.wednesday,
  'thursday': DateTime.thursday,
  'thu': DateTime.thursday,
  'friday': DateTime.friday,
  'fri': DateTime.friday,
  'saturday': DateTime.saturday,
  'sat': DateTime.saturday,
  'sunday': DateTime.sunday,
  'sun': DateTime.sunday,
};

/// A word of the input and where it sits.
class _Word {
  const _Word(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
  String get lower => text.toLowerCase();
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Reads quick-add text such as «جلسه با علی فردا ساعت ۵ عصر #کار @تلفن p1»
/// into a task. Pure and deterministic: [now] is the device's local time.
/// Ranges listed in [ignore] (dismissed by the user) stay part of the
/// title.
QuickTask parseQuickTask(
  String input, {
  required DateTime now,
  Set<(int, int)> ignore = const {},
}) {
  final text = latinDigits(input);
  final tokens = <QuickToken>[];
  bool free(int start, int end) =>
      !ignore.any((range) => start < range.$2 && range.$1 < end) &&
      !tokens.any((t) => start < t.end && t.start < end);
  void take(QuickTokenKind kind, int start, int end) {
    if (free(start, end)) {
      tokens.add(QuickToken(kind, start, end, input.substring(start, end)));
    }
  }

  DateTime? deadline;
  // {deadline}, which may hold spaces.
  for (final m in RegExp(r'\{([^{}]+)\}').allMatches(text)) {
    final inner = parseQuickTask(m.group(1)!, now: now);
    if (inner.day != null && free(m.start, m.end)) {
      deadline = inner.day;
      take(QuickTokenKind.deadline, m.start, m.end);
    }
  }

  QuickRecurrence? recurrence;
  final weekdayNames = _weekdays.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final weekdayPattern = weekdayNames.map(RegExp.escape).join('|');
  final repeated = RegExp(
    r'(^|\s)(?:every(!?)\s+(?:(\d+)\s+)?(days?|weeks?|months?|years?)|هر\s+(?:(\d+)\s+)?(روز|هفته|ماه|سال))(?:\s+(?:on\s+)?(\d{1,2})(?:ام|م|st|nd|rd|th))?(?=\s|$)',
    caseSensitive: false,
  );
  for (final match in repeated.allMatches(text)) {
    final start = match.start + match.group(1)!.length;
    final interval = int.tryParse(match.group(3) ?? match.group(5) ?? '1')!;
    final unit = match.group(4)?.toLowerCase() ?? match.group(6)!;
    final frequency = switch (unit) {
      'day' || 'days' || 'روز' => 'day',
      'week' || 'weeks' || 'هفته' => 'week',
      'month' || 'months' || 'ماه' => 'month',
      _ => 'year',
    };
    final monthDay = int.tryParse(match.group(7) ?? '');
    if (interval < 1 ||
        interval > 1000 ||
        monthDay != null &&
            (frequency != 'month' || monthDay < 1 || monthDay > 31) ||
        !free(start, match.end)) {
      continue;
    }
    recurrence = QuickRecurrence(
      frequency: frequency,
      interval: interval,
      basis: match.group(2) == '!' ? 'completion' : 'due',
      monthDay: monthDay,
    );
    take(QuickTokenKind.recurrence, start, match.end);
    break;
  }
  if (recurrence == null) {
    final repeatedWeekday = RegExp(
      '(^|\\s)(?:every|هر)\\s+($weekdayPattern)(?=\\s|\$)',
      caseSensitive: false,
    );
    for (final match in repeatedWeekday.allMatches(text)) {
      final start = match.start + match.group(1)!.length;
      if (!free(start, match.end)) continue;
      recurrence = QuickRecurrence(
        frequency: 'week',
        weekday: _weekdays[match.group(2)!.toLowerCase()],
      );
      take(QuickTokenKind.recurrence, start, match.end);
      break;
    }
  }

  final words = [
    for (final m in RegExp(r'\S+').allMatches(text))
      if (!tokens.any((t) => m.start < t.end && t.start < m.end))
        _Word(m.group(0)!, m.start, m.end),
  ];

  int? priority;
  String? project;
  String? section;
  final labels = <String>[];
  for (final w in words) {
    final p = RegExp(r'^(?:[pP]|!!)([1-4])$').firstMatch(w.text);
    if (p != null && free(w.start, w.end)) {
      priority = int.parse(p.group(1)!);
      take(QuickTokenKind.priority, w.start, w.end);
    } else if (w.text.length > 1 &&
        w.text.startsWith('#') &&
        free(w.start, w.end)) {
      project = input.substring(w.start + 1, w.end);
      take(QuickTokenKind.project, w.start, w.end);
    } else if (w.text.length > 1 &&
        w.text.startsWith('@') &&
        free(w.start, w.end)) {
      labels.add(input.substring(w.start + 1, w.end));
      take(QuickTokenKind.label, w.start, w.end);
    } else if (w.text.length > 1 &&
        w.text.startsWith('/') &&
        free(w.start, w.end)) {
      section = input.substring(w.start + 1, w.end);
      take(QuickTokenKind.section, w.start, w.end);
    }
  }

  final today = _day(now);
  DateTime? day;
  int? hour;
  var minute = 0;

  // Walk the words looking for date and time phrases, longest first.
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (!free(w.start, w.end)) continue;
    _Word? at(int k) => i + k < words.length ? words[i + k] : null;
    void span(QuickTokenKind kind, int count) =>
        take(kind, w.start, words[i + count - 1].end);
    final next = at(1)?.lower;

    // Dates.
    if (day == null) {
      final word = w.lower;
      int? offset = switch (word) {
        'امروز' || 'today' => 0,
        'فردا' || 'tomorrow' || 'tmr' => 1,
        'پس‌فردا' || 'پسفردا' => 2,
        _ => null,
      };
      if (offset != null) {
        day = today.add(Duration(days: offset));
        span(QuickTokenKind.date, 1);
        continue;
      }
      if (word == 'پس' && next == 'فردا') {
        day = today.add(const Duration(days: 2));
        span(QuickTokenKind.date, 2);
        i++;
        continue;
      }
      if ((word == 'هفته' || word == 'هفته‌ی') && next == 'بعد') {
        day = today.add(const Duration(days: 7));
        span(QuickTokenKind.date, 2);
        i++;
        continue;
      }
      if (word == 'next' && next == 'week') {
        day = today.add(const Duration(days: 7));
        span(QuickTokenKind.date, 2);
        i++;
        continue;
      }
      if ((word == 'ماه' && next == 'بعد') ||
          (word == 'next' && next == 'month')) {
        day = DateTime(today.year, today.month + 1, today.day);
        span(QuickTokenKind.date, 2);
        i++;
        continue;
      }
      // "in 3 days" / «۳ روز دیگر».
      final count = int.tryParse(word);
      if (count != null && next == 'روز' && at(2)?.lower == 'دیگر') {
        day = today.add(Duration(days: count));
        span(QuickTokenKind.date, 3);
        i += 2;
        continue;
      }
      if (word == 'in' &&
          int.tryParse(next ?? '') != null &&
          (at(2)?.lower == 'days' || at(2)?.lower == 'day')) {
        day = today.add(Duration(days: int.parse(next!)));
        span(QuickTokenKind.date, 3);
        i += 2;
        continue;
      }
      // Weekdays: «دوشنبه», «سه شنبه», «دوشنبه بعد», "monday", "next monday".
      var weekdayWords = 0;
      int? weekday = _weekdays[word];
      if (weekday != null) {
        weekdayWords = 1;
      } else if ((word == 'سه' || word == 'پنج' || word == 'یک') &&
          next == 'شنبه') {
        weekday = _weekdays['$wordشنبه'];
        weekdayWords = 2;
      } else if (word == 'next' && _weekdays[next ?? ''] != null) {
        weekday = _weekdays[next!];
        weekdayWords = 2;
      }
      if (weekday != null) {
        var ahead = (weekday - today.weekday + 7) % 7;
        if (ahead == 0) ahead = 7;
        final nextWeek = word == 'next' || at(weekdayWords)?.lower == 'بعد';
        if (nextWeek && word != 'next') weekdayWords++;
        if (nextWeek) ahead += 7;
        day = today.add(Duration(days: ahead));
        span(QuickTokenKind.date, weekdayWords);
        i += weekdayWords - 1;
        continue;
      }
      // «۱۵ مهر» (with an optional year) and "15 oct" / "oct 15".
      final number = int.tryParse(word);
      final jalaliMonth = _jalaliMonths[next];
      if (number != null &&
          jalaliMonth != null &&
          number >= 1 &&
          number <= 31) {
        final year = int.tryParse(at(2)?.lower ?? '');
        var count = 2;
        var j = JalaliDate.fromGregorian(today).year;
        if (year != null && year > 1300 && year < 1600) {
          j = year;
          count = 3;
        }
        var date = JalaliDate(j, jalaliMonth, number).toGregorian();
        if (year == null && date.isBefore(today)) {
          date = JalaliDate(j + 1, jalaliMonth, number).toGregorian();
        }
        day = _day(date);
        span(QuickTokenKind.date, count);
        i += count - 1;
        continue;
      }
      final monthFirst = _gregorianMonths[word];
      final dayAfter = int.tryParse(next ?? '');
      final gMonth = monthFirst ?? _gregorianMonths[next ?? ''];
      final gDay = monthFirst != null ? dayAfter : number;
      if (gMonth != null && gDay != null && gDay >= 1 && gDay <= 31) {
        var date = DateTime(today.year, gMonth, gDay);
        if (date.isBefore(today)) date = DateTime(today.year + 1, gMonth, gDay);
        day = date;
        span(QuickTokenKind.date, 2);
        i++;
        continue;
      }
    }

    // Times: «ساعت ۵», «ساعت ۱۷:۳۰», «ساعت ۵ عصر», «۵ عصر», "5pm", "at 17".
    if (hour == null) {
      var j = 0;
      final lead = w.lower;
      if (lead == 'ساعت' || lead == 'at') j = 1;
      final clock = at(j)?.lower;
      final m = clock == null
          ? null
          : RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)?$').firstMatch(clock);
      if (m != null) {
        var h = int.parse(m.group(1)!);
        final mm = int.tryParse(m.group(2) ?? '') ?? 0;
        final suffix = m.group(3);
        final part = at(j + 1)?.lower;
        var used = j + 1;
        final persianPart = switch (part) {
          'صبح' => 'am',
          'ظهر' => 'noon',
          'بعدازظهر' || 'عصر' || 'شب' => 'pm',
          _ => null,
        };
        if (persianPart != null) used++;
        final meridiem = suffix ?? persianPart;
        // A bare number counts as a time only after «ساعت»/"at" or with a
        // part of the day, so "3 apples" stays text.
        if ((j == 1 || meridiem != null) && h <= 23 && mm <= 59) {
          if (meridiem == 'pm' && h < 12) h += 12;
          if (meridiem == 'am' && h == 12) h = 0;
          if (meridiem == 'noon' && h < 6) h += 12;
          hour = h;
          minute = mm;
          span(QuickTokenKind.time, used);
          i += used - 1;
          continue;
        }
      }
    }
  }

  // A time with no date is today, or tomorrow once that time has passed.
  if (hour != null && day == null) {
    final at = DateTime(today.year, today.month, today.day, hour, minute);
    day = at.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  tokens.sort((a, b) => a.start.compareTo(b.start));
  final title = StringBuffer();
  var cursor = 0;
  for (final t in tokens) {
    title.write(input.substring(cursor, t.start));
    cursor = t.end;
  }
  title.write(input.substring(cursor));
  return QuickTask(
    title: title.toString().replaceAll(RegExp(r'\s+'), ' ').trim(),
    day: day,
    hour: hour,
    minute: minute,
    deadline: deadline,
    priority: priority,
    project: project,
    section: section,
    recurrence: recurrence,
    labels: labels,
    tokens: tokens,
  );
}
