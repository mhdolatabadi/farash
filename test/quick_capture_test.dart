import 'package:flutter_test/flutter_test.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/quick_capture.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'support/fake_tasks_api.dart';
import 'support/fake_sections_api.dart';

class _RecurringApi extends FakeTasksApi implements TimeApi {
  bool failRule = true;
  final paths = <String>[];
  Map<String, Object?>? schedule;
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    paths.add(path);
    schedule = body!['schedule'] as Map<String, Object?>;
    if (failRule) throw StateError('response lost');
    return {
      'recurrence': {'schedule': schedule, 'emitted': 0},
    };
  }
}

void main() {
  const inbox = Project(id: 'inbox', name: '', color: '#98503D', isInbox: true);
  const work = Project(id: 'work', name: 'کار', color: '#98503D');
  final now = DateTime(2026, 10, 14);
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);

  test(
    'Today fallback day preserves explicit dates and project default stays undated',
    () async {
      final api = FakeTasksApi();
      final session = QuickCaptureSession(
        api: api,
        token: () => 'token',
        projects: () => [inbox],
        defaultProject: () => inbox,
      );
      await session.capture(
        parseQuickTask('plain', now: now),
        'plain',
        calendar: 'jalali',
      );
      expect(api.all.last.due, isNull);
      await session.capture(
        parseQuickTask('fallback', now: now),
        'fallback',
        calendar: 'jalali',
        defaultDay: now,
      );
      expect(api.all.last.due!.day, now);
      await session.capture(
        parseQuickTask('explicit فردا', now: now),
        'explicit فردا',
        calendar: 'jalali',
        defaultDay: now,
      );
      expect(api.all.last.due!.day, DateTime(2026, 10, 15));
    },
  );

  test('section is resolved in the parsed project before creating', () async {
    final api = FakeTasksApi();
    final sections = FakeSectionsApi()..seed('work', 'برنامه');
    final session = QuickCaptureSession(
      api: api,
      sections: sections,
      token: () => 'token',
      projects: () => [inbox, work],
      defaultProject: () => inbox,
    );
    const raw = 'مطالعه #کار /برنامه';
    final task = await session.capture(
      parseQuickTask(raw, now: now),
      raw,
      calendar: 'jalali',
    );
    expect(task.projectId, 'work');
    expect(task.sectionId, sections.all.single.id);
    expect(task.title, 'مطالعه');
  });

  test('missing section rejects before any task is created', () async {
    final api = FakeTasksApi();
    final session = QuickCaptureSession(
      api: api,
      sections: FakeSectionsApi(),
      token: () => 'token',
      projects: () => [inbox],
      defaultProject: () => inbox,
    );
    const raw = 'مطالعه /گم‌شده';
    await expectLater(
      session.capture(parseQuickTask(raw, now: now), raw, calendar: 'jalali'),
      throwsException,
    );
    expect(api.all, isEmpty);
  });

  for (final candidates in [
    ('unknown', <Project>[inbox]),
    (
      'ambiguous',
      <Project>[
        inbox,
        work,
        const Project(id: 'other', name: 'کار', color: '#98503D'),
      ],
    ),
  ]) {
    test('${candidates.$1} project rejects before creating', () async {
      final api = FakeTasksApi();
      final session = QuickCaptureSession(
        api: api,
        token: () => 'token',
        projects: () => candidates.$2,
        defaultProject: () => inbox,
      );
      const raw = 'مطالعه #کار';
      await expectLater(
        session.capture(parseQuickTask(raw, now: now), raw, calendar: 'jalali'),
        throwsException,
      );
      expect(api.all, isEmpty);
    });
  }

  test('same section name in another project is never selected', () async {
    final api = FakeTasksApi();
    final sections = FakeSectionsApi()..seed('work', 'برنامه');
    final session = QuickCaptureSession(
      api: api,
      sections: sections,
      token: () => 'token',
      projects: () => [inbox, work],
      defaultProject: () => inbox,
    );
    const raw = 'مطالعه /برنامه';
    await expectLater(
      session.capture(parseQuickTask(raw, now: now), raw, calendar: 'jalali'),
      throwsException,
    );
    expect(api.all, isEmpty);
    sections.seed('inbox', 'برنامه');
    sections.seed('inbox', 'برنامه');
    await expectLater(
      session.capture(parseQuickTask(raw, now: now), raw, calendar: 'jalali'),
      throwsException,
    );
    expect(api.all, isEmpty);
  });

  test('incompatible explicit weekday fails before creating a task', () async {
    final api = _RecurringApi();
    final session = QuickCaptureSession(
      api: api,
      token: () => 'token',
      projects: () => [inbox],
      defaultProject: () => inbox,
    );
    const raw = 'کلاس هر دوشنبه فردا';
    await expectLater(
      session.capture(parseQuickTask(raw, now: now), raw, calendar: 'jalali'),
      throwsException,
    );
    expect(api.all, isEmpty);
    expect(api.paths, isEmpty);
  });

  test(
    'lost recurrence response retries rule on confirmed ID, never create',
    () async {
      final api = _RecurringApi();
      var token = 'token';
      final session = QuickCaptureSession(
        api: api,
        token: () => token,
        projects: () => [inbox],
        defaultProject: () => inbox,
      );
      const raw = 'مطالعه هر روز';
      final parsed = parseQuickTask(raw, now: now);
      await expectLater(
        session.capture(parsed, raw, calendar: 'jalali', now: now),
        throwsException,
      );
      expect(session.hasPendingRecurrence, isTrue);
      expect(api.all, hasLength(1));
      await expectLater(
        session.capture(
          parseQuickTask('دیگر', now: now),
          'دیگر',
          calendar: 'jalali',
        ),
        throwsException,
      );
      token = 'other';
      await expectLater(
        session.capture(parsed, raw, calendar: 'jalali'),
        throwsException,
      );
      expect(api.paths, hasLength(1));
      token = 'token';
      api.failRule = false;
      final task = await session.capture(parsed, raw, calendar: 'jalali');
      expect(api.all, hasLength(1));
      expect(api.paths, [
        '/api/v1/tasks/${task.id}/recurrence',
        '/api/v1/tasks/${task.id}/recurrence',
      ]);
      expect(session.hasPendingRecurrence, isFalse);
      expect((api.schedule!['rule'] as Map)['frequency'], 'day');
    },
  );
}
