import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/focus/focus_view.dart';
import 'package:farash/features/weaving/weaving_home.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'package:farash/features/time_tracking/time_tracking_view.dart';
import 'support/fake_projects_api.dart';
import 'support/fake_tasks_api.dart';

class TrackingFixture extends FakeTasksApi implements TimeApi {
  Map<String, dynamic>? active;
  final calls = <Map<String, Object?>>[];
  bool fail = false;
  bool failRead = false;
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (method == 'POST') {
      calls.add(body ?? {'stop': path});
      if (fail) throw const ApiException('offline');
      if (path.endsWith('/stop')) {
        final stopped = {
          ...active!,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        };
        active = null;
        return stopped;
      } else {
        active = {
          'id': 'entry-1',
          'task_id': body!['task_id'],
          'title': 'مطالعهٔ کتاب',
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'ended_at': null,
          'planned_end': body['focus_seconds'] == null
              ? null
              : DateTime.now()
                    .add(Duration(seconds: body['focus_seconds'] as int))
                    .toUtc()
                    .toIso8601String(),
          'source': body['source'],
        };
      }
      return active ?? {};
    }
    if (failRead) throw const ApiException('offline report');
    return {
      'active': active,
      'entries': <Map<String, dynamic>>[],
      'tasks': <Map<String, dynamic>>[],
      'seconds': 0,
      'today_seconds': 0,
      'server_now': DateTime.now().toUtc().toIso8601String(),
      'truncated': false,
    };
  }
}

void main() {
  setUp(() => debugTimeZoneOverride = 'Asia/Tehran');
  tearDown(() => debugTimeZoneOverride = null);
  testWidgets('focus records task time, survives navigation and pauses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = TrackingFixture()..seed('inbox', 'مطالعهٔ کتاب');
    final projects = ProjectsController(
      api: FakeProjectsApi(),
      token: () => 'token',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: FarashTheme.light(),
        home: HomeScreen(
          email: 'fixture@example.com',
          onLogout: () {},
          projects: projects,
          tasksApi: api,
          token: () => 'token',
          startView: StartView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final task = (await api.listTasks('token', 'inbox')).first;
    tester.widget<WeavingHome>(find.byType(WeavingHome)).onTaskFocus!(task);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('شروع تمرکز'));
    await tester.tap(find.text('شروع تمرکز'));
    await tester.pumpAndSettle();
    expect(api.active?['source'], 'focus');
    expect(api.calls.first['task_id'], task.id);
    expect(api.calls.first['focus_seconds'], 1500);
    await tester.tap(find.text('کارها').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('توقف ثبت زمان'), findsWidgets);
    await tester.tap(find.text('تمرکز').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('مکث'));
    await tester.tap(find.text('مکث'));
    await tester.pumpAndSettle();
    expect(api.active, isNull);
    expect(
      tester.widget<FocusView>(find.byType(FocusView)).controller.running,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'failed start retains retry key and does not fabricate a session',
    (tester) async {
      final api = TrackingFixture();
      final tracker = TimeTracker(api: api, token: () => 'token');
      await tester.pumpAndSettle();
      api.fail = true;
      const task = Task(id: 'task', projectId: 'inbox', title: 'work');
      expect(await tracker.start(task), isFalse);
      expect(tracker.active, isNull);
      final key = api.calls.first['request_key'];
      api.fail = false;
      expect(await tracker.start(task), isTrue);
      expect(api.calls.last['request_key'], key);
      tracker.dispose();
    },
  );
  testWidgets(
    'narrow large-text report and persistent control remain reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);
      final api = TrackingFixture();
      final tracker = TimeTracker(api: api, token: () => 'token');
      await tester.pumpAndSettle();
      await tracker.start(
        const Task(id: 'task', projectId: 'inbox', title: 'work'),
      );
      final projects = ProjectsController(
        api: FakeProjectsApi(),
        token: () => 'token',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: FarashTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                children: [
                  ActiveTimeBar(tracker: tracker, onOpen: () {}),
                  Expanded(
                    child: TimeTrackingView(
                      tracker: tracker,
                      tasksApi: api,
                      projects: projects,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.byTooltip('توقف ثبت زمان').first).dy,
        greaterThanOrEqualTo(24),
      );
      await tester.tap(find.byTooltip('توقف ثبت زمان').first);
      await tester.pumpAndSettle();
      expect(tracker.active, isNull);
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
      await tester.pumpAndSettle();
    },
  );
  testWidgets('authoritative start and stop survive a failed report refresh', (
    tester,
  ) async {
    final api = TrackingFixture();
    final tracker = TimeTracker(api: api, token: () => 'token');
    await tester.pumpAndSettle();
    api.failRead = true;
    expect(
      await tracker.start(
        const Task(id: 'task', projectId: 'inbox', title: 'work'),
      ),
      isTrue,
    );
    expect(tracker.active?.id, 'entry-1');
    expect(tracker.error, isNotNull);
    expect(await tracker.stop(tracker.active!), isTrue);
    expect(tracker.active, isNull);
    tracker.dispose();
  });
  testWidgets('same-name projects retain separate report groups', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProjectTimeGroups(
            tasks: [
              {
                'project_id': 'one',
                'project': 'پروژه',
                'title': 'اول',
                'seconds': 60,
              },
              {
                'project_id': 'two',
                'project': 'پروژه',
                'title': 'دوم',
                'seconds': 120,
              },
            ],
          ),
        ),
      ),
    );
    expect(find.text('پروژه · ۰۰:۰۱:۰۰'), findsOneWidget);
    expect(find.text('پروژه · ۰۰:۰۲:۰۰'), findsOneWidget);
    expect(find.text('پروژه · ۰۰:۰۳:۰۰'), findsNothing);
  });
  test('today gaps merge overlaps without inventing work', () {
    final now = DateTime(2026, 10, 16, 12);
    TimeEntry entry(int start, int end) => TimeEntry.fromJson({
      'id': '$start',
      'task_id': 'task',
      'title': 'work',
      'started_at': DateTime(2026, 10, 16, start).toUtc().toIso8601String(),
      'ended_at': DateTime(2026, 10, 16, end).toUtc().toIso8601String(),
      'planned_end': null,
      'source': 'manual',
    });
    final gaps = todayGaps([entry(8, 10), entry(9, 11)], now);
    expect(gaps.length, 2);
    expect(gaps.first.$2, DateTime(2026, 10, 16, 8).toUtc());
    expect(gaps.last.$1, DateTime(2026, 10, 16, 11).toUtc());
    expect(gaps.last.$2, now.toUtc());
  });
  test('time labels retain hours and clamp negative elapsed values', () {
    expect(
      trackedTime(const Duration(hours: 27, minutes: 2, seconds: 3)),
      '۲۷:۰۲:۰۳',
    );
    final entry = TimeEntry.fromJson({
      'id': '1',
      'task_id': 'task',
      'title': 'work',
      'started_at': '2026-10-16T12:00:00Z',
      'ended_at': null,
      'planned_end': '2026-10-16T12:25:00Z',
      'source': 'focus',
    });
    expect(
      entry.elapsed(DateTime.parse('2026-10-16T14:00:00Z')),
      const Duration(minutes: 25),
    );
    expect(
      entry.elapsed(DateTime.parse('2026-10-16T11:00:00Z')),
      Duration.zero,
    );
  });
}
