import 'package:farash/features/calendar/week_event_layout.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final week = DateTime(2026, 11, 21);

  Task timed(String id, int day, int hour, int minute, int duration) => Task(
    id: id,
    projectId: 'inbox',
    title: id,
    due: TaskDue.at(DateTime(2026, 11, day, hour, minute), 'UTC'),
    durationMinutes: duration,
  );

  test(
    'timed events keep proportional time and are assigned overlap lanes',
    () {
      final blocks = layoutWeekEvents([
        timed('first', 23, 12, 0, 90),
        timed('second', 23, 12, 30, 60),
        timed('third', 23, 14, 0, 30),
      ], week);
      final first = blocks.singleWhere((e) => e.task.id == 'first');
      final second = blocks.singleWhere((e) => e.task.id == 'second');
      final third = blocks.singleWhere((e) => e.task.id == 'third');
      expect(first.dayIndex, 2);
      expect(first.startMinute, 720);
      expect(first.endMinute, 810);
      expect(first.columns, 2);
      expect(second.columns, 2);
      expect(second.column, isNot(first.column));
      expect(third.columns, 1);
    },
  );

  test('a task crossing midnight appears on both adjacent dates', () {
    final task = timed('overnight', 22, 23, 30, 120);
    final events = layoutWeekEvents([task], week);
    expect(events.length, 2);
    expect(events[0].dayIndex, 1);
    expect(events[0].startMinute, 1410);
    expect(events[0].endMinute, 1440);
    expect(events[1].dayIndex, 2);
    expect(events[1].startMinute, 0);
    expect(events[1].endMinute, 90);
  });

  test('untimed tasks stay out of the time grid', () {
    final task = Task(
      id: 'all-day',
      projectId: 'inbox',
      title: 'All day',
      due: TaskDue.onDay(DateTime(2026, 11, 23)),
    );
    expect(layoutWeekEvents([task], week), isEmpty);
    expect(weekDayIndex(task, week), 2);
  });

  test('tasks outside the week are clipped without becoming new tasks', () {
    final blocks = layoutWeekEvents([
      timed('too-late', 30, 10, 0, 60),
      timed('friday', 27, 23, 40, 100),
    ], week);
    expect(blocks.length, 1);
    expect(blocks.single.task.id, 'friday');
    expect(blocks.single.endMinute, 1440);
  });
}
