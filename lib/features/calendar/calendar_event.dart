/// An appointment owned by the current account, independent of task completion.
class CalendarEvent {
  const CalendarEvent({required this.id, required this.title, required this.start,
    required this.end, required this.timeZone, required this.version});

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: json['id'] as String, title: json['title'] as String,
    start: DateTime.parse(json['start_at'] as String),
    end: DateTime.parse(json['end_at'] as String),
    timeZone: json['time_zone'] as String, version: json['version'] as int,
  );

  final String id, title, timeZone;
  final DateTime start, end;
  final int version;
  DateTime get localStart => start.toLocal();
  DateTime get localEnd => end.toLocal();
}

class CalendarEventDraft {
  const CalendarEventDraft({required this.title, required this.start,
    required this.end, required this.timeZone});
  final String title, timeZone;
  final DateTime start, end;
  Map<String, Object?> toJson() => {
    'title': title.trim(), 'start_at': start.toUtc().toIso8601String(),
    'end_at': end.toUtc().toIso8601String(), 'time_zone': timeZone,
  };
}
