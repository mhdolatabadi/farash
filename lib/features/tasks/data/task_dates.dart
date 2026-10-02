import 'package:farash/core/calendar/date_labels.dart';

/// When a task is due, as the API returns it: a whole day, or a moment in
/// the time zone it was planned in.
class TaskDue {
  const TaskDue({required this.date, this.datetime, this.timezone});

  factory TaskDue.fromJson(Map<String, dynamic> json) => TaskDue(
    date: json['date'] as String,
    datetime: json['datetime'] == null
        ? null
        : DateTime.parse(json['datetime'] as String),
    timezone: json['timezone'] as String?,
  );

  /// An all-day due on [day].
  factory TaskDue.onDay(DateTime day) => TaskDue(date: dateKey(day));

  /// A timed due at [local] device time, planned in [timezone].
  factory TaskDue.at(DateTime local, String timezone) => TaskDue(
    date: dateKey(local),
    datetime: local.toUtc(),
    timezone: timezone,
  );

  /// The local day, YYYY-MM-DD, in the zone it was planned in.
  final String date;

  /// The moment, when a time is set.
  final DateTime? datetime;
  final String? timezone;

  bool get isTimed => datetime != null;

  /// The moment on this device's clock.
  DateTime? get localTime => datetime?.toLocal();

  /// The day to show: a timed due shows on this device's day of it.
  DateTime get day => isTimed ? dayOf(localTime!) : parseDateKey(date);

  bool isOverdue(DateTime now) =>
      isTimed ? datetime!.isBefore(now) : day.isBefore(dayOf(now));

  Map<String, Object?> toJson() => isTimed
      ? {'datetime': datetime!.toUtc().toIso8601String(), 'timezone': timezone}
      : {'date': date};

  @override
  bool operator ==(Object other) =>
      other is TaskDue &&
      other.date == date &&
      other.datetime == datetime &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(date, datetime, timezone);
}

/// Due, deadline and duration together, as the editor sets them.
class TaskDates {
  const TaskDates({this.due, this.deadline, this.durationMinutes});

  final TaskDue? due;

  /// YYYY-MM-DD.
  final String? deadline;

  /// Only with a timed due.
  final int? durationMinutes;

  bool get isEmpty => due == null && deadline == null;

  /// Every field, nulls included, so the API sets or clears each one.
  Map<String, Object?> toJson() => {
    'due': due?.toJson(),
    'deadline': deadline,
    'duration_minutes': due?.isTimed == true ? durationMinutes : null,
  };

  @override
  bool operator ==(Object other) =>
      other is TaskDates &&
      other.due == due &&
      other.deadline == deadline &&
      other.durationMinutes == durationMinutes;

  @override
  int get hashCode => Object.hash(due, deadline, durationMinutes);
}

String dateKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
