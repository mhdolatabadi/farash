import 'package:flutter_test/flutter_test.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/focus/focus_session_storage.dart';

void main() {
  test('snapshots validate schema and round-trip metadata', () {
    const value = FocusSessionData(
      minutes: 25,
      remainingMs: 0,
      deadlineMs: 1795176000000,
      taskTitle: 'نوشتن پایان نامه',
      taskId: 'task-1',
      entryId: 'entry-1',
    );
    final decoded = FocusSessionData.decode(value.encode());
    expect(decoded?.minutes, 25);
    expect(decoded?.deadlineMs, value.deadlineMs);
    expect(decoded?.taskTitle, value.taskTitle);
    expect(decoded?.entryId, 'entry-1');
    expect(
      FocusSessionData.decode('{"version":1,"minutes":99,"remaining_ms":0}'),
      isNull,
    );
    expect(FocusSessionData.decode('not-json'), isNull);
  });

  test('secure storage keys isolate accounts and servers', () async {
    final store = MemoryCalendarSettingsStore();
    final a = FocusSessionStorage(
      account: 'A@EXAMPLE.COM',
      server: 'https://one.example',
      store: store,
    );
    final b = FocusSessionStorage(
      account: 'b@example.com',
      server: 'https://one.example',
      store: store,
    );
    final otherServer = FocusSessionStorage(
      account: 'a@example.com',
      server: 'https://two.example',
      store: store,
    );
    await a.save(const FocusSessionData(minutes: 5, remainingMs: 120000));
    expect((await a.read())?.remainingMs, 120000);
    expect(await b.read(), isNull);
    expect(await otherServer.read(), isNull);
    await a.save(null);
    expect(await a.read(), isNull);
  });

  test('restart catches up a running wall-clock deadline', () {
    var now = DateTime(2026, 11, 20, 11);
    final first = FocusController(now: () => now);
    first.start();
    final deadline = first.deadline!;
    first.dispose();

    now = now.add(const Duration(minutes: 9));
    final restored = FocusController(now: () => now);
    addTearDown(restored.dispose);
    restored.restoreState(
      mode: 25,
      remaining: Duration.zero,
      deadline: deadline,
      title: 'تمرکز روی کار',
    );
    expect(restored.running, isTrue);
    expect(restored.remaining, const Duration(minutes: 16));
    expect(restored.taskTitle, 'تمرکز روی کار');
    now = now.add(const Duration(minutes: 16));
    restored.refresh();
    expect(restored.finished, isTrue);
    expect(restored.running, isFalse);
  });

  test('paused and expired sessions do not restart after process death', () {
    var now = DateTime(2026, 11, 20, 11);
    final paused = FocusController(now: () => now);
    addTearDown(paused.dispose);
    paused.restoreState(mode: 5, remaining: const Duration(minutes: 3));
    now = now.add(const Duration(hours: 5));
    paused.refresh();
    expect(paused.running, isFalse);
    expect(paused.remaining, const Duration(minutes: 3));

    final expired = FocusController(now: () => now);
    addTearDown(expired.dispose);
    expired.restoreState(
      mode: 25,
      remaining: Duration.zero,
      deadline: now.subtract(const Duration(minutes: 5)),
    );
    expect(expired.remaining, Duration.zero);
    expect(expired.finished, isTrue);
    expect(expired.running, isFalse);
  });
}
