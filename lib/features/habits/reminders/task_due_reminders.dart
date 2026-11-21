import 'dart:convert';

import 'package:farash/features/tasks/data/task.dart';

/// Opt-in, at-due-time reminders for timed open tasks. Date-only tasks are
/// intentionally excluded: they have no wall-clock moment to notify about.
class TaskDueReminder {
  const TaskDueReminder({
    required this.taskId,
    required this.projectId,
    required this.title,
    required this.at,
  });

  final String taskId, projectId, title;
  final DateTime at;

  int get id => taskDueReminderId(taskId, at);

  String encode() => jsonEncode({
    'kind': 'task-due-reminder',
    'task': taskId,
    'project': projectId,
    'title': title,
    'at': at.toUtc().millisecondsSinceEpoch,
  });

  static TaskDueReminder? decode(String? raw) {
    if (raw == null || !raw.startsWith('{')) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['kind'] != 'task-due-reminder' ||
          data['task'] is! String ||
          data['project'] is! String ||
          data['title'] is! String ||
          data['at'] is! int) {
        return null;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(
        data['at'] as int,
        isUtc: true,
      );
      return TaskDueReminder(
        taskId: data['task'] as String,
        projectId: data['project'] as String,
        title: data['title'] as String,
        at: at,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Keep below Android's per-app alarm limit, leaving room for habit alarms.
const maxTaskDueReminders = 150;
const taskReminderHorizon = Duration(days: 14);

List<TaskDueReminder> planTaskDueReminders(
  Iterable<Task> tasks,
  DateTime now, {
  Duration horizon = taskReminderHorizon,
}) {
  final until = now.add(horizon);
  final reminders = <TaskDueReminder>[];
  for (final task in tasks) {
    final at = task.due?.datetime;
    if (task.isCompleted ||
        at == null ||
        !at.isAfter(now) ||
        at.isAfter(until)) {
      continue;
    }
    reminders.add(
      TaskDueReminder(
        taskId: task.id,
        projectId: task.projectId,
        title: task.title,
        at: at,
      ),
    );
  }
  reminders.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime == 0 ? a.taskId.compareTo(b.taskId) : byTime;
  });
  return reminders.length > maxTaskDueReminders
      ? reminders.sublist(0, maxTaskDueReminders)
      : reminders;
}

/// A stable, Android-safe ID. The task namespace is distinct from habits.
int taskDueReminderId(String taskId, DateTime at) {
  var hash = 0x811c9dc5;
  for (final unit
      in 'task-due/$taskId/${at.toUtc().millisecondsSinceEpoch}'.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
