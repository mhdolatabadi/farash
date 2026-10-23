import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/reminders/habit_reminders.dart';
import 'package:farash/features/habits/reminders/reminder_plan.dart';
import 'package:web/web.dart' as web;

/// Web reminders: browsers cannot schedule a notification, so they show
/// only while the app is open. Web Push is a later step.
class BrowserHabitReminders extends HabitReminders {
  BrowserHabitReminders({super.clock});

  static bool get supported => globalContext.has('Notification');

  /// A timer that wakes this late, as after the computer slept, has missed
  /// its moment and stays quiet.
  static const _late = Duration(minutes: 30);

  final _timers = <Timer>[];
  final _shown = <int, (ReminderPayload, web.Notification)>{};

  @override
  Future<bool> requestPermission() async {
    if (web.Notification.permission == 'granted') return true;
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart == 'granted';
  }

  @override
  Future<void> apply(List<PlannedReminder> plan, List<Habit> habits) async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _closeAnswered(habits);
    final now = this.now();
    for (final reminder in plan) {
      _timers.add(Timer(reminder.at.difference(now), () => _show(reminder)));
    }
  }

  void _closeAnswered(List<Habit> habits) {
    final byId = {for (final h in habits) h.id: h};
    _shown.removeWhere((_, shown) {
      final (payload, notification) = shown;
      final habit = byId[payload.habitId];
      final answered =
          habit == null ||
          !habit.hasReminder ||
          habit.entries.containsKey(payload.day);
      if (answered) notification.close();
      return answered;
    });
  }

  void _show(PlannedReminder reminder) {
    if (now().difference(reminder.at) > _late ||
        web.Notification.permission != 'granted') {
      return;
    }
    try {
      final notification = web.Notification(
        reminder.title,
        web.NotificationOptions(
          body: reminder.body,
          tag: '${reminder.id}',
          icon: 'icons/Icon-192.png',
          lang: 'fa',
          dir: 'rtl',
        ),
      );
      notification.onclick = (web.Event _) {
        web.window.focus();
        notification.close();
        opened.value = reminder.habitId;
      }.toJS;
      _shown[reminder.id] = (reminder.payload, notification);
    } catch (_) {
      // Mobile browsers only show notifications from a service worker.
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }
}
