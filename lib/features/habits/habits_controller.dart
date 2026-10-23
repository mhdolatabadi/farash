import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_stats.dart';
import 'package:farash/features/habits/reminders/habit_reminders.dart';

abstract interface class HabitsApi {
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

/// One editor's create intent, retained across uncertain responses and rebuilds.
class HabitCreateAttempt {
  final String requestKey =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  String? _token;
  Map<String, Object?>? _payload;
  Habit? _confirmed;
  Future<Habit?>? _inFlight;
}

enum HabitSort { manual, name, color, score }

/// The account's habits, with optimistic check-ins that roll back when the
/// server refuses them.
class HabitsController extends ChangeNotifier {
  HabitsController({
    required this.api,
    required this.token,
    this.reminders,
    DateTime? now,
  }) : _now = now;

  final HabitsApi api;

  /// Follows every change, so the device reminds about the current habits.
  final HabitReminders? reminders;
  final String? Function() token;
  final DateTime? _now;

  List<Habit> _habits = const [];
  final _stats = <String, HabitStats>{};
  final _entryQueues = <(String, int), Future<void>>{};
  bool loading = false, showArchived = false;
  HabitSort sort = HabitSort.manual;
  String? error;

  /// A short message for a failed change, shown once.
  final message = ValueNotifier<String?>(null);

  bool _disposed = false;

  int get today => epochDay(_now ?? DateTime.now());

  List<Habit> get all => _habits;

  /// The habits to list, in the chosen order.
  List<Habit> get visible {
    final list = [
      for (final h in _habits)
        if (showArchived || !h.archived) h,
    ];
    switch (sort) {
      case HabitSort.manual:
        break;
      case HabitSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case HabitSort.color:
        list.sort((a, b) => a.color.compareTo(b.color));
      case HabitSort.score:
        list.sort(
          (a, b) => stats(b).currentScore.compareTo(stats(a).currentScore),
        );
    }
    return list;
  }

  Habit? byId(String id) => _habits.where((h) => h.id == id).firstOrNull;

  HabitStats stats(Habit habit) {
    final cached = _stats[habit.id];
    if (cached != null &&
        identical(cached.habit, habit) &&
        cached.today == today) {
      return cached;
    }
    return _stats[habit.id] = HabitStats.of(habit, today);
  }

  void _set(List<Habit> habits) {
    _habits = habits;
    if (_disposed) return;
    reminders?.sync(habits);
    notifyListeners();
  }

  void _replace(Habit habit) =>
      _set([for (final h in _habits) h.id == habit.id ? habit : h]);

  Future<Map<String, dynamic>?> _call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final current = token();
    if (current == null) return null;
    final result = await api.habitRequest(current, method, path, body: body);
    return current == token() ? result : null;
  }

  static String _path(String id) => '/api/v1/habits/${Uri.encodeComponent(id)}';

  Future<void> load() async {
    loading = true;
    error = null;
    if (!_disposed) notifyListeners();
    try {
      final data = await _call('GET', '/api/v1/habits');
      if (data != null) {
        _habits = [
          for (final h in data['habits'] as List)
            Habit.fromJson(h as Map<String, dynamic>),
        ];
        reminders?.sync(_habits);
      }
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<Habit?> create(HabitDraft draft, {HabitCreateAttempt? attempt}) {
    final intent = attempt ?? HabitCreateAttempt();
    return intent._inFlight ??= _create(draft, intent).whenComplete(() {
      intent._inFlight = null;
    });
  }

  Future<Habit?> _create(HabitDraft draft, HabitCreateAttempt attempt) async {
    final current = token();
    if (current == null || _disposed) return null;
    attempt._token ??= current;
    if (attempt._token != current) return null;
    attempt._payload ??= Map.unmodifiable(draft.toJson());
    try {
      var habit = attempt._confirmed;
      if (habit == null) {
        final data = await _call('POST', '/api/v1/habits', {
          ...attempt._payload!,
          'request_key': attempt.requestKey,
        });
        if (data == null || _disposed) return null;
        habit = Habit.fromJson(data['habit'] as Map<String, dynamic>);
        attempt._confirmed = habit;
      }
      // If the draft changed after an uncertain response, first recover the
      // original create, then edit that same habit instead of creating again.
      if (jsonEncode(attempt._payload) != jsonEncode(draft.toJson())) {
        final data = await _call('PATCH', _path(habit.id), draft.toJson());
        if (data == null || _disposed) return null;
        habit = Habit.fromJson(data['habit'] as Map<String, dynamic>);
        attempt._confirmed = habit;
      }
      _set([
        for (final h in _habits)
          if (h.id != habit.id) h,
        habit,
      ]);
      return habit;
    } catch (e) {
      if (!_disposed) message.value = 'عادت ساخته نشد: $e';
      return null;
    }
  }

  Future<bool> update(Habit habit, HabitDraft changes) async {
    try {
      final data = await _call('PATCH', _path(habit.id), changes.toJson());
      if (data == null) return false;
      _replace(Habit.fromJson(data['habit'] as Map<String, dynamic>));
      return true;
    } catch (e) {
      message.value = 'تغییر ذخیره نشد: $e';
      return false;
    }
  }

  Future<bool> delete(Habit habit) async {
    final before = _habits;
    _set([
      for (final h in _habits)
        if (h.id != habit.id) h,
    ]);
    try {
      await _call('DELETE', _path(habit.id));
      return true;
    } catch (e) {
      _set(before);
      message.value = 'عادت حذف نشد: $e';
      return false;
    }
  }

  /// Moves [habit] to [index] of the manual order.
  Future<void> reorder(Habit habit, int index) async {
    final before = _habits;
    final list = [..._habits]..removeWhere((h) => h.id == habit.id);
    list.insert(index.clamp(0, list.length), habit);
    _set([for (final (i, h) in list.indexed) h.copyWith(sortOrder: i)]);
    try {
      await _call('POST', '/api/v1/habits/reorder', {
        'habit_ids': [for (final h in list) h.id],
      });
    } catch (e) {
      _set(before);
      message.value = 'ترتیب ذخیره نشد: $e';
    }
  }

  /// Records [entry] for [day], or clears the day when it is null.
  Future<void> setEntry(Habit habit, int day, HabitEntry? entry) =>
      _enqueueEntry(habit, day, (_) => entry);

  // Keep every tap, but send one change per day at a time. Its rollback then
  // finishes before the next intent reads or changes that day's value.
  Future<void> _enqueueEntry(
    Habit habit,
    int day,
    HabitEntry? Function(HabitEntry?) next,
  ) {
    final key = (habit.id, day);
    final previous = _entryQueues[key] ?? Future<void>.value();
    late final Future<void> operation;
    operation = previous
        .then((_) async {
          if (_disposed) return;
          final current = byId(habit.id) ?? habit;
          await _commitEntry(current, day, next(current.entries[day]));
        })
        .whenComplete(() {
          if (identical(_entryQueues[key], operation)) _entryQueues.remove(key);
        });
    _entryQueues[key] = operation;
    return operation;
  }

  Future<void> _commitEntry(Habit habit, int day, HabitEntry? entry) async {
    final current = byId(habit.id) ?? habit;
    final entries = {...current.entries};
    if (entry == null) {
      entries.remove(day);
    } else {
      entries[day] = entry;
    }
    _replace(current.copyWith(entries: entries));
    final path = '${_path(habit.id)}/entries/${dayKey(day)}';
    try {
      if (entry == null) {
        await _call('DELETE', path);
      } else {
        await _call('PUT', path, {'value': entry.value, 'skip': entry.skip});
      }
    } catch (e) {
      final latest = byId(habit.id);
      if (latest != null) {
        final restored = {...latest.entries};
        if (current.entries[day] case final old?) {
          restored[day] = old;
        } else {
          restored.remove(day);
        }
        _replace(latest.copyWith(entries: restored));
      }
      if (!_disposed) message.value = 'ثبت نشد: $e';
    }
  }

  /// «انجام شد» on a reminder: records [day] as done for a yes/no habit.
  Future<void> markDone(String habitId, int day) async {
    if (byId(habitId) == null) await load();
    final habit = byId(habitId);
    if (habit == null || habit.isNumeric) return;
    await setEntry(habit, day, const HabitEntry(value: 1));
  }

  /// Loop's toggle for a yes/no habit: unknown → done → not done → skipped.
  Future<void> toggle(Habit habit, int day) => _enqueueEntry(
    habit,
    day,
    (entry) => switch (entry) {
      null => const HabitEntry(value: 1),
      HabitEntry(skip: true) => null,
      HabitEntry(value: > 0) => const HabitEntry(value: 0),
      _ => const HabitEntry(value: 0, skip: true),
    },
  );

  @override
  void dispose() {
    _disposed = true;
    message.dispose();
    super.dispose();
  }
}
