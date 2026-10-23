import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habits_controller.dart';

import 'support/fake_habits_api.dart';

class DelayedEntries extends FakeHabitsApi {
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  bool failFirst = false;
  int entryRequests = 0;

  @override
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (path.contains('/entries/')) {
      entryRequests++;
      if (entryRequests == 1) {
        firstStarted.complete();
        await releaseFirst.future;
        if (failFirst) throw StateError('first write refused');
      }
    }
    return super.habitRequest(token, method, path, body: body);
  }
}

void main() {
  for (final failFirst in [false, true]) {
    test(
      'same-day taps wait for earlier ${failFirst ? 'failure' : 'success'}',
      () async {
        final api = DelayedEntries()..failFirst = failFirst;
        api.seed('Read');
        final controller = HabitsController(api: api, token: () => 't');
        addTearDown(controller.dispose);
        await controller.load();
        final habit = controller.all.single;
        final day = controller.today;
        final first = controller.toggle(habit, day);
        await api.firstStarted.future;
        final second = controller.toggle(habit, day);
        await Future<void>.delayed(Duration.zero);
        expect(api.entryRequests, 1, reason: 'same-day writes cannot overtake');
        api.releaseFirst.complete();
        await Future.wait([first, second]);
        expect(api.entryRequests, 2);
        final expected = failFirst ? 1.0 : 0.0;
        expect(controller.all.single.entries[day]!.value, expected);
        final stored = (api.habits.single['entries'] as List).single as Map;
        expect(stored['value'], expected);
        expect(controller.message.value, failFirst ? isNotNull : isNull);
      },
    );
  }

  test('a pending day does not block another day', () async {
    final api = DelayedEntries()..seed('Read');
    final controller = HabitsController(api: api, token: () => 't');
    addTearDown(controller.dispose);
    await controller.load();
    final habit = controller.all.single;
    final day = controller.today;
    final first = controller.setEntry(habit, day, const HabitEntry(value: 1));
    await api.firstStarted.future;
    await controller.setEntry(habit, day - 1, const HabitEntry(value: 1));
    expect(api.entryRequests, 2);
    api.releaseFirst.complete();
    await first;
    expect(controller.all.single.entries.length, 2);
  });
}
