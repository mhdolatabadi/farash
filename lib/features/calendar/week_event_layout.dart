import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/features/tasks/data/task.dart';

/// A positioned portion of a timed task in one calendar day.
class WeekEventPlacement {
  const WeekEventPlacement({
    required this.task,
    required this.dayIndex,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final Task task;
  final int dayIndex;
  final int startMinute;
  final int endMinute;
  final int column;
  final int columns;
}

class _Candidate {
  _Candidate(this.task, this.dayIndex, this.start, this.end);

  final Task task;
  final int dayIndex;
  final int start;
  final int end;
  int column = 0;
}

/// Convert timed due dates into a seven-day time grid, split across midnight.
/// Overlapping blocks get distinct lanes instead of obscuring each other.
/// The due time is the anchor and durationMinutes is the visible span; where
/// no duration is provided we display a clearly provisional 30-minute block.
List<WeekEventPlacement> layoutWeekEvents(
  List<Task> tasks,
  DateTime weekStart,
) {
  final days = [
    for (var i = 0; i < 7; i++)
      DateTime(weekStart.year, weekStart.month, weekStart.day + i),
  ];
  final candidates = <_Candidate>[];
  for (final task in tasks) {
    final start = task.due?.localTime;
    if (start == null) continue;
    final length = (task.durationMinutes ?? 30).clamp(15, 1440).toInt();
    final end = start.add(Duration(minutes: length));
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final next = DateTime(day.year, day.month, day.day + 1);
      if (!start.isBefore(next) || !end.isAfter(day)) continue;
      final visibleStart = start.isAfter(day) ? start : day;
      final visibleEnd = end.isBefore(next) ? end : next;
      final startMinute = visibleStart.hour * 60 + visibleStart.minute;
      final endMinute = visibleEnd == next
          ? 1440
          : visibleEnd.hour * 60 + visibleEnd.minute;
      if (endMinute > startMinute) {
        candidates.add(_Candidate(task, i, startMinute, endMinute));
      }
    }
  }
  final result = <WeekEventPlacement>[];
  for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
    final events = candidates.where((e) => e.dayIndex == dayIndex).toList()
      ..sort((a, b) {
        final byStart = a.start.compareTo(b.start);
        if (byStart != 0) return byStart;
        final byEnd = b.end.compareTo(a.end);
        return byEnd != 0 ? byEnd : a.task.id.compareTo(b.task.id);
      });
    var group = <_Candidate>[];
    var active = <_Candidate>[];
    var groupEnd = 0;
    var maxLanes = 0;

    void flush() {
      for (final candidate in group) {
        result.add(
          WeekEventPlacement(
            task: candidate.task,
            dayIndex: candidate.dayIndex,
            startMinute: candidate.start,
            endMinute: candidate.end,
            column: candidate.column,
            columns: maxLanes,
          ),
        );
      }
      group = <_Candidate>[];
      active = <_Candidate>[];
      groupEnd = 0;
      maxLanes = 0;
    }

    for (final event in events) {
      if (group.isNotEmpty && event.start >= groupEnd) flush();
      active.removeWhere((e) => e.end <= event.start);
      var lane = 0;
      while (active.any((e) => e.column == lane)) {
        lane++;
      }
      event.column = lane;
      group.add(event);
      active.add(event);
      if (event.end > groupEnd) groupEnd = event.end;
      if (lane + 1 > maxLanes) maxLanes = lane + 1;
    }
    if (group.isNotEmpty) flush();
  }
  return result;
}

/// The calendar day of a task, including timed due dates in device time.
int? weekDayIndex(Task task, DateTime weekStart) {
  final due = task.due;
  if (due == null) return null;
  final index = daysBetween(weekStart, due.day);
  return index < 0 || index >= 7 ? null : index;
}
