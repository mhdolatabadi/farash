import 'package:flutter/foundation.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/reminders/reminder_plan.dart';
import 'package:farash/features/habits/reminders/local_reminders.dart';
import 'package:farash/features/habits/reminders/browser_reminders_stub.dart'
    if (dart.library.js_interop) 'package:farash/features/habits/reminders/browser_reminders.dart';

/// Shows each habit's reminders on this device. The habits come from the
/// server; the notifications, and their text, never leave the device.
abstract class HabitReminders {
  HabitReminders({DateTime Function()? clock}) : now = clock ?? DateTime.now;

  /// Exact local notifications on Android, notifications while the app is
  /// open on the web, and nothing elsewhere.
  static HabitReminders? forPlatform() {
    if (kIsWeb) {
      return BrowserHabitReminders.supported ? BrowserHabitReminders() : null;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return LocalHabitReminders();
    }
    return null;
  }

  final DateTime Function() now;

  /// The habit whose reminder the user opened, for the app to show.
  final opened = ValueNotifier<String?>(null);

  List<Habit>? _next;
  Future<void>? _running;

  /// Replans every reminder from [habits]. Calls made while one runs are
  /// merged into one more run with the latest habits.
  Future<void> sync(Iterable<Habit> habits) {
    _next = habits.toList();
    return _running ??= _drain();
  }

  Future<void> _drain() async {
    try {
      for (var habits = _next; habits != null; habits = _next) {
        _next = null;
        try {
          await apply(planReminders(habits, now()), habits);
        } catch (e) {
          debugPrint('habit reminders: $e');
        }
      }
    } finally {
      _running = null;
    }
  }

  /// Makes the device's pending reminders match [plan]. [habits] tells
  /// which shown reminders are answered and can go.
  @protected
  Future<void> apply(List<PlannedReminder> plan, List<Habit> habits);

  /// Asks to show notifications. Browsers only allow this from a tap.
  Future<bool> requestPermission();

  /// Removes every habit reminder, as on sign-out.
  Future<void> clear() async {
    _next = null;
    await _running;
    await sync(const []);
  }

  @mustCallSuper
  void dispose() => opened.dispose();
}
