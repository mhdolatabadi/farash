import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:farash/app/app_configuration.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/reminders/habit_reminders.dart';
import 'package:farash/features/habits/reminders/reminder_plan.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const habitDoneAction = 'habit_done';
const habitLaterAction = 'habit_later';

/// Loop's «بعداً».
const habitSnooze = Duration(minutes: 15);

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_stat_habit'),
);

NotificationDetails _details({required bool canMarkDone}) =>
    NotificationDetails(
      android: AndroidNotificationDetails(
        'habit_reminders',
        'یادآور عادت‌ها',
        channelDescription: 'در ساعتی که برای هر عادت انتخاب کرده‌اید.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        color: const Color(0xFF0E7490),
        actions: [
          if (canMarkDone)
            const AndroidNotificationAction(habitDoneAction, 'انجام شد'),
          const AndroidNotificationAction(habitLaterAction, 'بعداً'),
        ],
      ),
    );

Future<void> _useDeviceTimeZone() async {
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation(await deviceTimeZone()));
  } catch (_) {
    tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
  }
}

tz.TZDateTime _wallClock(DateTime at) =>
    tz.TZDateTime(tz.local, at.year, at.month, at.day, at.hour, at.minute);

Future<void> _snooze(
  FlutterLocalNotificationsPlugin plugin,
  ReminderPayload payload,
) async {
  final snoozed = payload.snoozed();
  await plugin.zonedSchedule(
    id: snoozed.id,
    scheduledDate: tz.TZDateTime.now(tz.local).add(habitSnooze),
    notificationDetails: _details(canMarkDone: payload.canMarkDone),
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    title: payload.title,
    body: payload.body,
    payload: snoozed.encode(),
  );
}

/// Records the day as done with the saved session, without the app's UI.
/// When that fails, the reminder comes back so the answer is not lost.
Future<void> _markDone(
  FlutterLocalNotificationsPlugin plugin,
  ReminderPayload payload,
) async {
  try {
    final base = AppConfiguration.apiBaseUri;
    final token = await SecureSessionStore().readToken();
    if (base == null || token == null) throw StateError('signed out');
    await ApiClient(base).habitRequest(
      token,
      'PUT',
      '/api/v1/habits/${Uri.encodeComponent(payload.habitId)}'
          '/entries/${dayKey(payload.day)}',
      body: {'value': 1, 'skip': false},
    );
  } catch (_) {
    await plugin.show(
      id: payload.id,
      title: payload.title,
      body: 'ثبت نشد. برنامه را باز کنید و دوباره امتحان کنید.',
      notificationDetails: _details(canMarkDone: payload.canMarkDone),
      payload: payload.encode(),
    );
  }
}

/// Runs in its own isolate when «انجام شد» or «بعداً» is pressed, even if
/// the app is closed.
@pragma('vm:entry-point')
Future<void> habitReminderBackgroundAction(
  NotificationResponse response,
) async {
  final payload = ReminderPayload.decode(response.payload);
  if (payload == null) return;
  WidgetsFlutterBinding.ensureInitialized();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: _initSettings);
  switch (response.actionId) {
    case habitDoneAction:
      await _markDone(plugin, payload);
    case habitLaterAction:
      await _useDeviceTimeZone();
      await _snooze(plugin, payload);
  }
}

/// Android reminders: exact alarms where the system allows them, inexact
/// ones otherwise. They survive a reboot through the plugin's receiver.
class LocalHabitReminders extends HabitReminders {
  LocalHabitReminders({super.clock, FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  late final Future<void> _ready = _init();

  /// Records a day checked from a notification while the app runs, so the
  /// list updates at once; without it the request goes out on its own.
  Future<void> Function(String habitId, int day)? onDone;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _init() async {
    await _useDeviceTimeZone();
    await _plugin.initialize(
      settings: _initSettings,
      onDidReceiveNotificationResponse: _respond,
      onDidReceiveBackgroundNotificationResponse: habitReminderBackgroundAction,
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch != null && launch.didNotificationLaunchApp) {
      if (launch.notificationResponse case final response?) _respond(response);
    }
  }

  void _respond(NotificationResponse response) {
    final payload = ReminderPayload.decode(response.payload);
    if (payload == null) return;
    switch (response.actionId) {
      case habitDoneAction:
        final done = onDone;
        unawaited(
          done == null
              ? _markDone(_plugin, payload)
              : done(payload.habitId, payload.day),
        );
      case habitLaterAction:
        unawaited(_snooze(_plugin, payload));
      default:
        opened.value = payload.habitId;
    }
  }

  /// Starts listening for taps on reminders before any habit loads.
  Future<void> start() => _ready;

  @override
  Future<bool> requestPermission() async {
    await _ready;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  static bool _answered(Map<String, Habit> habits, ReminderPayload payload) {
    final habit = habits[payload.habitId];
    return habit == null ||
        habit.archived ||
        !habit.hasReminder ||
        habit.entries.containsKey(payload.day);
  }

  @override
  Future<void> apply(List<PlannedReminder> plan, List<Habit> habits) async {
    await _ready;
    final byId = {for (final h in habits) h.id: h};
    final planned = {for (final r in plan) r.id: r};
    final current = <int>{};
    for (final request in await _plugin.pendingNotificationRequests()) {
      final payload = ReminderPayload.decode(request.payload);
      if (payload == null) continue;
      final keep = payload.snooze
          ? !_answered(byId, payload)
          : planned[request.id]?.payload.encode() == request.payload;
      if (keep) {
        current.add(request.id);
      } else {
        await _plugin.cancel(id: request.id);
      }
    }
    // A reminder already on screen goes once its day is recorded.
    for (final shown in await _plugin.getActiveNotifications()) {
      final payload = ReminderPayload.decode(shown.payload);
      if (payload != null && shown.id != null && _answered(byId, payload)) {
        await _plugin.cancel(id: shown.id!);
      }
    }
    if (plan.every((r) => current.contains(r.id))) return;
    final mode = await _android?.canScheduleExactNotifications() == true
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final reminder in plan) {
      if (current.contains(reminder.id)) continue;
      await _plugin.zonedSchedule(
        id: reminder.id,
        scheduledDate: _wallClock(reminder.at),
        notificationDetails: _details(canMarkDone: reminder.canMarkDone),
        androidScheduleMode: mode,
        title: reminder.title,
        body: reminder.body,
        payload: reminder.payload.encode(),
      );
    }
  }
}
