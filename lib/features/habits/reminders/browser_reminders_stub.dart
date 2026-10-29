import 'package:farash/features/habits/reminders/habit_reminders.dart';

/// Stands in for the web scheduler on platforms without `dart:js_interop`.
abstract class BrowserHabitReminders extends HabitReminders {
  static bool get supported => false;

  factory BrowserHabitReminders() =>
      throw UnsupportedError('Browser notifications need the web.');
}
