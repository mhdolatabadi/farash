import 'package:flutter/widgets.dart';
import 'package:farash/core/calendar/calendar_settings.dart';

/// Hands the calendar settings down the tree and rebuilds what reads them.
class CalendarScope extends InheritedNotifier<CalendarSettings> {
  const CalendarScope({
    super.key,
    required CalendarSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static final _defaults = CalendarSettings();

  /// The app's settings, or Jalali with Saturday first outside a scope.
  static CalendarSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CalendarScope>()?.notifier ??
      _defaults;
}
