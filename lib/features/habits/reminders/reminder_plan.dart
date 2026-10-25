import 'dart:convert';

import 'package:farash/features/habits/habit.dart';

/// One notification to show for a habit on one day.
class PlannedReminder {
  const PlannedReminder({
    required this.habitId,
    required this.day,
    required this.at,
    required this.title,
    required this.body,
    required this.canMarkDone,
  });

  final String habitId;

  /// The [epochDay] the reminder belongs to.
  final int day;

  /// Local wall-clock time; a DST gap moves it forward like any local time.
  final DateTime at;
  final String title, body;

  /// Only a yes/no habit can be checked from the notification.
  final bool canMarkDone;

  int get id => reminderId(habitId, day);

  ReminderPayload get payload => ReminderPayload(
    habitId: habitId,
    day: day,
    title: title,
    body: body,
    canMarkDone: canMarkDone,
    at: at,
  );
}

/// How many days ahead are scheduled. The plan is redone on every start,
/// resume and habit change, so this only matters for a device that stays
/// unopened for longer.
const reminderHorizonDays = 14;

/// Android stops accepting alarms at around 500 per app on some devices.
const maxPlannedReminders = 300;

/// The reminders due after [now], earliest first: the habit's weekdays, not
/// archived, and not on a day that is already recorded, as in Loop.
List<PlannedReminder> planReminders(
  Iterable<Habit> habits,
  DateTime now, {
  int days = reminderHorizonDays,
}) {
  final plan = <PlannedReminder>[];
  for (final habit in habits) {
    final minute = habit.reminderMinute;
    if (minute == null || habit.archived) continue;
    for (var offset = 0; offset < days; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      final at = DateTime(
        date.year,
        date.month,
        date.day,
        minute ~/ 60,
        minute % 60,
      );
      final day = epochDay(date);
      if (!at.isAfter(now) ||
          !habit.remindsOn(date.weekday) ||
          habit.entries.containsKey(day)) {
        continue;
      }
      plan.add(
        PlannedReminder(
          habitId: habit.id,
          day: day,
          at: at,
          title: habit.name,
          body: reminderBody(habit),
          canMarkDone: !habit.isNumeric,
        ),
      );
    }
  }
  plan.sort((a, b) => a.at.compareTo(b.at));
  return plan.length > maxPlannedReminders
      ? plan.sublist(0, maxPlannedReminders)
      : plan;
}

/// The habit's question, as Loop shows it, or a plain prompt.
String reminderBody(Habit habit) =>
    habit.question.isNotEmpty ? habit.question : 'وقت ثبت «${habit.name}» است.';

/// A stable notification id for a habit's day: FNV-1a, kept positive and
/// within 31 bits as Android requires.
int reminderId(String habitId, int day, {bool snooze = false}) {
  var hash = 0x811c9dc5;
  for (final unit in '$habitId/$day${snooze ? '/snooze' : ''}'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// What a reminder notification carries, so that its actions can work in
/// the background without the habit list: snoozing shows the same text.
class ReminderPayload {
  const ReminderPayload({
    required this.habitId,
    required this.day,
    required this.title,
    required this.body,
    required this.canMarkDone,
    this.at,
    this.snooze = false,
  });

  final String habitId, title, body;
  final int day;
  final bool canMarkDone, snooze;

  /// When it was planned; a pending notification with the same payload
  /// needs no rescheduling.
  final DateTime? at;

  int get id => reminderId(habitId, day, snooze: snooze);

  String encode() => jsonEncode({
    'kind': 'habit-reminder',
    'habit': habitId,
    'day': day,
    'title': title,
    'body': body,
    'done': canMarkDone,
    if (at case final at?) 'at': at.millisecondsSinceEpoch,
    if (snooze) 'snooze': true,
  });

  ReminderPayload snoozed() => ReminderPayload(
    habitId: habitId,
    day: day,
    title: title,
    body: body,
    canMarkDone: canMarkDone,
    snooze: true,
  );

  /// The payload of a habit reminder, or null for anything else.
  static ReminderPayload? decode(String? text) {
    if (text == null || !text.startsWith('{')) return null;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['kind'] != 'habit-reminder') return null;
      final at = j['at'] as int?;
      return ReminderPayload(
        habitId: j['habit'] as String,
        day: j['day'] as int,
        title: j['title'] as String,
        body: j['body'] as String,
        canMarkDone: j['done'] == true,
        at: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
        snooze: j['snooze'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
