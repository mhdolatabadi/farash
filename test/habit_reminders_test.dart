import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_editor.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/habits/reminders/habit_reminders.dart';
import 'package:farash/features/habits/reminders/reminder_plan.dart';

import 'support/fake_habits_api.dart';

/// Records what would be scheduled instead of touching the platform.
class RecordingReminders extends HabitReminders {
  RecordingReminders({super.clock});

  final plans = <List<PlannedReminder>>[];
  bool allow = true;
  int permissionRequests = 0;

  /// Holds each apply until completed, to observe merged syncs.
  Future<void> Function()? gate;

  List<PlannedReminder> get last => plans.last;

  @override
  Future<void> apply(List<PlannedReminder> plan, List<Habit> habits) async {
    await gate?.call();
    plans.add(plan);
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allow;
  }
}

// Thursday 22 October 2026, noon.
final now = DateTime(2026, 10, 22, 12);
final today = epochDay(now);

Habit habit({
  String id = 'h1',
  int? minute = 9 * 60,
  int days = Habit.everyDay,
  bool archived = false,
  HabitKind kind = HabitKind.boolean,
  String question = '',
  Map<int, HabitEntry> entries = const {},
}) => Habit(
  id: id,
  name: 'ورزش',
  question: question,
  kind: kind,
  targetValue: kind == HabitKind.numeric ? 8 : 0,
  reminderMinute: minute,
  reminderDays: days,
  archived: archived,
  entries: entries,
);

int bit(int weekday) => 1 << (weekday - 1);

void main() {
  group('plan', () {
    test('every chosen day ahead, at the local minute, earliest first', () {
      final plan = planReminders([
        habit(minute: 13 * 60 + 30),
        habit(id: 'h2', minute: 8 * 60),
      ], now);
      // h1 still fires today at 13:30; h2's 08:00 has passed.
      expect(plan.first.habitId, 'h1');
      expect(plan.first.at, DateTime(2026, 10, 22, 13, 30));
      expect(plan.where((r) => r.habitId == 'h1'), hasLength(14));
      expect(plan.where((r) => r.habitId == 'h2'), hasLength(13));
      expect(
        plan.where((r) => r.habitId == 'h2').first.at,
        DateTime(2026, 10, 23, 8),
      );
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].at.isBefore(plan[i - 1].at), isFalse);
      }
    });

    test('only on the chosen weekdays', () {
      final plan = planReminders([
        habit(days: bit(DateTime.saturday) | bit(DateTime.monday)),
      ], now);
      expect(plan, hasLength(4));
      expect(plan.map((r) => r.at.weekday).toSet(), {
        DateTime.saturday,
        DateTime.monday,
      });
    });

    test('a recorded day stays quiet, whatever was recorded', () {
      final plan = planReminders([
        habit(
          minute: 18 * 60,
          entries: {
            today: const HabitEntry(value: 0, skip: true),
            today + 1: const HabitEntry(value: 0),
          },
        ),
      ], now);
      expect(plan.first.day, today + 2);
    });

    test('no reminder, or archived, plans nothing', () {
      expect(planReminders([habit(minute: null)], now), isEmpty);
      expect(planReminders([habit(archived: true)], now), isEmpty);
    });

    test('a reminder at this very minute has passed', () {
      final plan = planReminders([habit(minute: 12 * 60)], now);
      expect(plan.first.day, today + 1);
    });

    test('caps the number of alarms', () {
      final many = [for (var i = 0; i < 40; i++) habit(id: 'h$i')];
      expect(planReminders(many, now), hasLength(maxPlannedReminders));
    });

    test('the text is the question, as in Loop, and numeric habits '
        'cannot be checked from it', () {
      final asked = planReminders([
        habit(question: 'امروز ورزش کردید؟'),
      ], now).first;
      expect(asked.body, 'امروز ورزش کردید؟');
      expect(asked.canMarkDone, isTrue);
      final numeric = planReminders([
        habit(kind: HabitKind.numeric),
      ], now).first;
      expect(numeric.body, contains('ورزش'));
      expect(numeric.canMarkDone, isFalse);
    });
  });

  group('payload', () {
    test('round-trips and ignores other payloads', () {
      final reminder = planReminders([habit()], now).first;
      final decoded = ReminderPayload.decode(reminder.payload.encode())!;
      expect(decoded.habitId, 'h1');
      expect(decoded.day, reminder.day);
      expect(decoded.title, 'ورزش');
      expect(decoded.canMarkDone, isTrue);
      expect(decoded.at, reminder.at);
      expect(decoded.id, reminder.id);
      expect(ReminderPayload.decode(null), isNull);
      expect(ReminderPayload.decode('focus'), isNull);
      expect(ReminderPayload.decode('{"kind":"other"}'), isNull);
      expect(ReminderPayload.decode('{broken'), isNull);
    });

    test('ids are stable, positive 31-bit, and differ for a snooze', () {
      final id = reminderId('h1', today);
      expect(reminderId('h1', today), id);
      expect(id, inInclusiveRange(0, 0x7fffffff));
      expect(reminderId('h1', today + 1), isNot(id));
      expect(reminderId('h1', today, snooze: true), isNot(id));
      final payload = planReminders([habit()], now).first.payload;
      expect(payload.snoozed().id, isNot(payload.id));
      expect(
        ReminderPayload.decode(payload.snoozed().encode())!.snooze,
        isTrue,
      );
    });
  });

  test('syncs made while one runs merge into one more', () async {
    final reminders = RecordingReminders(clock: () => now);
    addTearDown(reminders.dispose);
    final first = Completer<void>();
    reminders.gate = () => first.future;
    final a = reminders.sync([habit()]);
    reminders.sync([habit(minute: 10 * 60)]);
    final c = reminders.sync([habit(minute: 11 * 60)]);
    expect(identical(a, c), isTrue);
    reminders.gate = null;
    first.complete();
    await c;
    expect(reminders.plans, hasLength(2));
    expect(reminders.last.first.at.hour, 11);
    await reminders.clear();
    expect(reminders.last, isEmpty);
  });

  test('the controller keeps reminders in step with the habits', () async {
    final api = FakeHabitsApi();
    api.seed('ورزش')['reminder_minute'] = 18 * 60;
    final reminders = RecordingReminders(clock: () => now);
    final controller = HabitsController(
      api: api,
      token: () => 't',
      reminders: reminders,
      now: now,
    );
    addTearDown(controller.dispose);
    addTearDown(reminders.dispose);
    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(reminders.last.first.day, today);

    await controller.markDone('h1', today);
    await Future<void>.delayed(Duration.zero);
    expect(reminders.last.first.day, today + 1);
    expect(api.calls.last.$1, 'PUT');
    expect(api.calls.last.$3, {'value': 1.0, 'skip': false});

    final h = controller.byId('h1')!;
    await controller.update(h, const HabitDraft(reminder: HabitReminder.off()));
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.last.$3, {
      'reminder_minute': null,
      'reminder_days': Habit.everyDay,
    });
    expect(reminders.last, isEmpty);
  });

  test('labels', () {
    expect(formatMinuteOfDay(9 * 60 + 5), '۰۹:۰۵');
    expect(reminderDaysLabel(Habit.everyDay), 'هر روز');
    expect(
      reminderDaysLabel(bit(DateTime.monday) | bit(DateTime.saturday)),
      'شنبه و دوشنبه',
    );
    expect(
      reminderDaysLabel(
        bit(DateTime.monday) | bit(DateTime.saturday) | bit(DateTime.sunday),
      ),
      'شنبه، یکشنبه و دوشنبه',
    );
    expect(
      reminderDaysLabel(Habit.everyDay & ~bit(DateTime.friday)),
      'هر روز به‌جز جمعه',
    );
  });

  testWidgets('the editor sets a reminder time and weekdays', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeHabitsApi()..seed('ورزش');
    final reminders = RecordingReminders(clock: () => now);
    final controller = HabitsController(
      api: api,
      token: () => 't',
      reminders: reminders,
      now: now,
    );
    addTearDown(controller.dispose);
    addTearDown(reminders.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: FarashTheme.light(),
        home: HabitEditor(controller: controller, habit: controller.byId('h1')),
      ),
    );
    expect(find.text('خاموش'), findsOneWidget);
    expect(find.byTooltip('جمعه'), findsNothing);

    await tester.tap(find.text('خاموش'));
    await tester.pumpAndSettle();
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(Dialog)),
    ).okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();
    expect(find.text('۰۹:۰۰'), findsOneWidget);
    expect(reminders.permissionRequests, 1);
    expect(find.byTooltip('جمعه'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      ),
      findsNWidgets(7),
    );

    // Friday off.
    await tester.tap(find.byTooltip('جمعه'));
    await tester.pump();
    await tester.tap(find.text('ذخیره'));
    await tester.pumpAndSettle();
    final patch = api.calls.last;
    expect(patch.$1, 'PATCH');
    expect(patch.$3!['reminder_minute'], 9 * 60);
    expect(patch.$3!['reminder_days'], Habit.everyDay & ~bit(DateTime.friday));
  });

  testWidgets('a refused permission says how to allow it', (tester) async {
    final api = FakeHabitsApi()..seed('ورزش');
    final reminders = RecordingReminders(clock: () => now)..allow = false;
    final controller = HabitsController(
      api: api,
      token: () => 't',
      reminders: reminders,
      now: now,
    );
    addTearDown(controller.dispose);
    addTearDown(reminders.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FarashTheme.light(),
        home: HabitEditor(controller: controller),
      ),
    );
    await tester.tap(find.text('خاموش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تنظیمات دستگاه'), findsOneWidget);
    // Turning the reminder off clears the warning.
    await tester.tap(find.byTooltip('خاموش کردن یادآور'));
    await tester.pump();
    expect(find.textContaining('تنظیمات دستگاه'), findsNothing);
    expect(find.text('خاموش'), findsOneWidget);
  });
}
