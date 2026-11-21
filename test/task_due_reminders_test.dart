import 'package:farash/features/habits/reminders/reminder_plan.dart';
import 'package:farash/features/habits/reminders/task_due_reminders.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter_test/flutter_test.dart';

Task _task(
  String id, {
  TaskDue? due,
  bool completed = false,
  String title = 'تکمیل گزارش',
}) => Task(
  id: id,
  projectId: 'inbox',
  title: title,
  due: due,
  completedAt: completed ? DateTime.utc(2026, 11, 20) : null,
);

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);
  TaskDue at(DateTime when) =>
      TaskDue(date: '2026-11-21', datetime: when, timezone: 'Asia/Tehran');

  test('only future timed open tasks create alarms', () {
    final planned = planTaskDueReminders([
      _task('past', due: at(now.subtract(const Duration(minutes: 1)))),
      _task('all-day', due: TaskDue.onDay(DateTime(2026, 11, 21))),
      _task(
        'finished',
        due: at(now.add(const Duration(hours: 2))),
        completed: true,
      ),
      _task('future', due: at(now.add(const Duration(hours: 1)))),
      _task('too-far', due: at(now.add(const Duration(days: 15)))),
    ], now);
    expect(planned.map((p) => p.taskId), ['future']);
  });

  test('earliest 150 alarms win, with deterministic tie order', () {
    final list = [
      for (var i = 160; i >= 0; i--)
        _task(
          'task${i.toString().padLeft(3, '0')}',
          due: at(now.add(const Duration(minutes: 1))),
        ),
    ];
    final reminders = planTaskDueReminders(list, now);
    expect(reminders.length, maxTaskDueReminders);
    expect(reminders.first.taskId, 'task000');
    expect(reminders.last.taskId, 'task149');
  });

  test('payload survives encode/decode, with no unrelated kinds accepted', () {
    final reminder = planTaskDueReminders([
      _task('one', due: at(now.add(const Duration(minutes: 5)))),
    ], now).single;
    final decoded = TaskDueReminder.decode(reminder.encode())!;
    expect(decoded.taskId, reminder.taskId);
    expect(decoded.projectId, 'inbox');
    expect(decoded.at, reminder.at);
    expect(decoded.id, reminder.id);
    expect(TaskDueReminder.decode(null), isNull);
    expect(TaskDueReminder.decode('{bad'), isNull);
    expect(TaskDueReminder.decode('{"kind":"habit-reminder"}'), isNull);
  });

  test('IDs are stable per task and due moment, distinct from habit IDs', () {
    final later = now.add(const Duration(minutes: 3));
    expect(
      taskDueReminderId('one', later),
      taskDueReminderId('one', later.toLocal()),
    );
    expect(
      taskDueReminderId('one', later),
      isNot(taskDueReminderId('one', later.add(const Duration(minutes: 1)))),
    );
    expect(taskDueReminderId('one', later), isNot(reminderId('one', 100)));
  });
}
