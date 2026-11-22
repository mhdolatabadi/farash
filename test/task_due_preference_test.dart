import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/features/habits/reminders/task_due_preference.dart';

void main() {
  test('task due consent is isolated by account and server', () async {
    final store = MemoryCalendarSettingsStore();
    final alice = TaskDueNotificationPreference(
      account: 'Alice@Example.COM',
      server: 'https://one.example',
      store: store,
    );
    final sameAccount = TaskDueNotificationPreference(
      account: 'alice@example.com',
      server: 'https://one.example',
      store: store,
    );
    final bob = TaskDueNotificationPreference(
      account: 'bob@example.com',
      server: 'https://one.example',
      store: store,
    );
    final otherServer = TaskDueNotificationPreference(
      account: 'alice@example.com',
      server: 'https://two.example',
      store: store,
    );

    expect(await alice.read(), isFalse);
    await alice.write(true);
    expect(await sameAccount.read(), isTrue);
    expect(await bob.read(), isFalse);
    expect(await otherServer.read(), isFalse);
    await bob.write(true);
    await alice.write(false);
    expect(await alice.read(), isFalse);
    expect(await bob.read(), isTrue);
    expect(store.values.keys.every((key) => !key.contains('@')), isTrue);
  });

  test('legacy device-wide consent is not inherited by a new account', () async {
    final store = MemoryCalendarSettingsStore();
    await store.write('task_due_notifications', 'on');
    final choice = TaskDueNotificationPreference(
      account: 'new@example.com',
      server: 'https://one.example',
      store: store,
    );
    expect(await choice.read(), isFalse);
  });
}
