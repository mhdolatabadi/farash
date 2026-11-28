import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/features/calendar/calendar_event.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';
import 'support/fake_calendar_events_api.dart';

CalendarEventDraft draft(String title) => CalendarEventDraft(
  title: title,
  start: DateTime.utc(2026, 11, 23, 9),
  end: DateTime.utc(2026, 11, 23, 10),
  timeZone: 'UTC',
);

class DelayedEventsApi implements CalendarEventsApi {
  final replies = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> eventRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) {
    final reply = Completer<Map<String, dynamic>>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  test('lost create response reuses intent and reconciles the edited draft', () async {
    final api = FakeCalendarEventsApi()..loseCreateResponse = true;
    final controller = CalendarEventsController(api: api, token: () => 'alice');
    addTearDown(controller.dispose);
    final attempt = CalendarEventCreateAttempt();
    expect(await controller.save(draft('جلسه'), attempt: attempt), isNull);
    expect(api.rows, hasLength(1));
    expect(controller.error, isNotNull);
    final saved = await controller.save(draft('جلسه ویرایش‌شده'), attempt: attempt);
    expect(api.rows, hasLength(1));
    expect(saved?.title, 'جلسه ویرایش‌شده');
    expect(api.calls.map((call) => call.$1), ['POST', 'POST', 'PATCH']);
    expect(api.calls[0].$3!['request_key'], api.calls[1].$3!['request_key']);
    expect(controller.error, isNull);
  });

  test('delete and undo keep events separate and stale edits are rejected', () async {
    final api = FakeCalendarEventsApi();
    final controller = CalendarEventsController(api: api, token: () => 'alice');
    addTearDown(controller.dispose);
    final event = (await controller.save(draft('جلسه'), attempt: CalendarEventCreateAttempt()))!;
    final edited = await controller.save(draft('نسخه دوم'), existing: event,
      attempt: CalendarEventCreateAttempt());
    expect(edited?.version, 2);
    expect(await controller.save(draft('نسخه قدیمی'), existing: event,
      attempt: CalendarEventCreateAttempt()), isNull);
    expect(controller.error, contains('تغییر کرده'));
    expect(await controller.setDeleted(edited!, true), isTrue);
    expect(controller.events, isEmpty);
    expect(await controller.setDeleted(edited, false), isTrue);
    expect(controller.events.single.title, 'نسخه دوم');
  });

  test('late response cannot expose data after account change', () async {
    var token = 'alice';
    final api = DelayedEventsApi();
    final controller = CalendarEventsController(api: api, token: () => token);
    addTearDown(controller.dispose);
    final loading = controller.load(DateTime(2026, 11, 21), DateTime(2026, 11, 28));
    final check = expectLater(loading, throwsA(isA<Exception>()));
    token = 'bob';
    api.replies.single.complete({'events': []});
    await check;
    expect(controller.events, isEmpty);
  });

  test('older week response does not replace current week', () async {
    final api = DelayedEventsApi();
    final controller = CalendarEventsController(api: api, token: () => 'alice');
    addTearDown(controller.dispose);
    final first = controller.load(DateTime(2026, 11, 21), DateTime(2026, 11, 28));
    final second = controller.load(DateTime(2026, 11, 28), DateTime(2026, 12, 5));
    api.replies[1].complete({'events': [{...draft('جدید').toJson(), 'id': 'new', 'version': 1}]});
    await second;
    api.replies[0].complete({'events': [{...draft('قدیمی').toJson(), 'id': 'old', 'version': 1}]});
    expect(await first, isEmpty);
    expect(controller.events.single.id, 'new');
  });
}
