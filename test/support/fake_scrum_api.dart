import 'dart:convert';
import 'dart:typed_data';
import 'package:farash/features/portability/export_api.dart';
// Synthetic, deterministic Scrum API for tests and native review only.
import 'package:farash/features/scrum/scrum.dart';
import 'package:farash/features/tasks/data/task.dart';
import '../../tool/time_preview.dart' show PreviewTimeApi;

class FakeScrumApi extends PreviewTimeApi implements ScrumApi, ExportApi {
  @override
  Future<Uint8List> exportAccount(String token) async => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'farash-export',
        'version': 1,
        'exported_at': '2026-10-21T00:00:00Z',
        'preferences': <String, Object?>{},
        'records': {'tasks': <Object?>[]},
      }),
    ),
  );

  FakeScrumApi() {
    seed('inbox', 'مطالعهٔ فصل اول کتاب');
    final a = seed('personal', 'مطالعهٔ فصل دوم کتاب');
    final b = seed('personal', 'خلاصه‌نویسی آموخته‌ها');
    seed('personal', 'انتخاب فصل بعدی');
    metadata[a.id] = {
      'issue_type': 'story',
      'points': 3,
      'sprint_id': 'sprint-1',
      'acceptance': 'یادداشت نکات اصلی فصل',
      'stage': 'todo',
    };
    metadata[b.id] = {
      'issue_type': 'task',
      'points': 2,
      'sprint_id': 'sprint-1',
      'acceptance': '',
      'stage': 'doing',
    };
  }
  String method = 'scrum', state = 'planned';
  bool fail = false;
  final metadata = <String, Map<String, dynamic>>{};
  final calls = <(String, String, Map<String, Object?>?)>[];
  String review = '', retro = '';
  @override
  Future<Map<String, dynamic>> agileRequest(
    String token,
    String verb,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (fail) throw StateError('offline');
    if (verb != 'GET') {
      calls.add((verb, path, body));
      if (path.endsWith('/agile')) {
        method = body!['method'] as String;
      } else if (path.contains('/items/')) {
        metadata[path.split('/').last] = {...body!};
      } else if (path.endsWith('/start')) {
        state = 'active';
      } else if (path.endsWith('/close')) {
        state = 'closed';
        review = body!['review'] as String? ?? '';
        retro = body['retro'] as String? ?? '';
        for (final entry in metadata.entries) {
          if (!all.firstWhere((t) => t.id == entry.key).isCompleted) {
            entry.value['sprint_id'] = body['sprint_id'];
          }
        }
      } else if (path.endsWith('/notes')) {
        review = body!['review'] as String;
        retro = body['retro'] as String;
      }
    }
    final now = DateTime(2026, 10, 20, 12).toUtc();
    final tasks = await listTasks(token, 'personal', showCompleted: true);
    final done = tasks
        .where(
          (t) => t.isCompleted && metadata[t.id]?['sprint_id'] == 'sprint-1',
        )
        .length;
    final snapshot = tasks
        .where((t) => metadata[t.id]?['sprint_id'] == 'sprint-1')
        .toList();
    Map<String, dynamic> event(
      String kind,
      int count,
      int points,
      DateTime at,
    ) => {
      'sprint_id': 'sprint-1',
      'at': at.toIso8601String(),
      'kind': kind,
      'scope_points': 5,
      'remaining_points': points,
      'scope_count': 2,
      'remaining_count': count,
    };
    return {
      'method': method,
      'items': [
        for (final t in tasks)
          {
            'task': _json(t),
            'issue_type': 'task',
            'points': null,
            'sprint_id': null,
            'acceptance': '',
            'stage': 'todo',
            ...?metadata[t.id],
          },
      ],
      'sprints': [
        {
          'id': 'sprint-1',
          'name': 'نوبت مطالعه',
          'goal': 'فصل دوم را بفهمم و خلاصه کنم.',
          'starts_on': '2026-10-20',
          'ends_on': '2026-11-02',
          'capacity': 8,
          'state': state,
          'committed_points': state == 'planned' ? 0 : 5,
          'committed_count': state == 'planned' ? 0 : 2,
          'scope_points': 5,
          'done_points': done == 0 ? 0 : 3,
          'scope_count': 2,
          'done_count': done,
          'unestimated': 0,
          'tracked_seconds': 1800,
          'review': review,
          'retro': retro,
        },
      ],
      'events': state == 'planned'
          ? <Map<String, dynamic>>[]
          : [
              event('start', 2, 5, now.subtract(const Duration(days: 1))),
              event('task_changed', 2 - done, done == 0 ? 5 : 2, now),
            ],
      'scope': state == 'planned'
          ? <Map<String, dynamic>>[]
          : [
              for (final t in snapshot)
                {
                  'sprint_id': 'sprint-1',
                  'task_id': t.id,
                  'title': t.title,
                  'points': metadata[t.id]?['points'],
                  'completed': t.isCompleted,
                  'removed_at': null,
                },
            ],
    };
  }

  Map<String, dynamic> _json(Task t) => {
    'id': t.id,
    'project_id': t.projectId,
    'title': t.title,
    'description': t.description,
    'priority': t.priority.level,
    'sort_order': t.sortOrder,
    'completed_at': t.completedAt?.toIso8601String(),
    'parent_id': t.parentId,
    'label_ids': t.labelIds,
  };
}
