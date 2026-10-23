import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habits_controller.dart';

import 'support/fake_habits_api.dart';

class LostCreateResponse extends FakeHabitsApi {
  final requests = <Map<String, Object?>>[];
  final responses = <String, Map<String, dynamic>>{};
  final started = Completer<void>();
  Completer<void>? release;
  bool loseFirst = true;

  @override
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (method == 'POST' && path == '/api/v1/habits') {
      requests.add(Map.of(body!));
      if (!started.isCompleted) started.complete();
      if (release != null) await release!.future;
      final key = body['request_key'] as String;
      final result = responses[key] ??=
          jsonDecode(
                jsonEncode(
                  await super.habitRequest(
                    token,
                    method,
                    path,
                    body: Map.of(body)..remove('request_key'),
                  ),
                ),
              )
              as Map<String, dynamic>;
      if (loseFirst) {
        loseFirst = false;
        throw StateError('response lost after commit');
      }
      return result;
    }
    return super.habitRequest(token, method, path, body: body);
  }
}

void main() {
  test(
    'lost create response retries frozen identity without duplicates',
    () async {
      final api = LostCreateResponse();
      final controller = HabitsController(api: api, token: () => 't');
      addTearDown(controller.dispose);
      final attempt = HabitCreateAttempt();
      const draft = HabitDraft(name: 'Read');
      expect(await controller.create(draft, attempt: attempt), isNull);
      expect(api.habits, hasLength(1));
      final saved = await controller.create(draft, attempt: attempt);
      expect(saved!.id, api.habits.single['id']);
      expect(api.requests, hasLength(2));
      expect(api.requests[0], api.requests[1]);
      expect(controller.all, hasLength(1));
      expect(api.habits, hasLength(1));
    },
  );
  test(
    'edited uncertain draft recovers original then updates same habit',
    () async {
      final api = LostCreateResponse();
      final controller = HabitsController(api: api, token: () => 't');
      addTearDown(controller.dispose);
      final attempt = HabitCreateAttempt();
      await controller.create(const HabitDraft(name: 'Read'), attempt: attempt);
      final saved = await controller.create(
        const HabitDraft(name: 'Read a chapter'),
        attempt: attempt,
      );
      expect(saved!.name, 'Read a chapter');
      expect(api.requests[1]['name'], 'Read');
      expect(api.habits.single['name'], 'Read a chapter');
      expect(api.habits, hasLength(1));
    },
  );
  test(
    'concurrent submit shares one request and session change blocks retry',
    () async {
      final api = LostCreateResponse()..release = Completer<void>();
      var token = 'first';
      final controller = HabitsController(api: api, token: () => token);
      addTearDown(controller.dispose);
      final attempt = HabitCreateAttempt();
      const draft = HabitDraft(name: 'Read');
      final a = controller.create(draft, attempt: attempt);
      await api.started.future;
      final b = controller.create(draft, attempt: attempt);
      expect(identical(a, b), isTrue);
      api.release!.complete();
      await Future.wait([a, b]);
      token = 'second';
      expect(await controller.create(draft, attempt: attempt), isNull);
      expect(api.requests, hasLength(1));
      expect(controller.all, isEmpty);
    },
  );
}
