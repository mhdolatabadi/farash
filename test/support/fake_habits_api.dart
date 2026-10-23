import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/habits/habits_controller.dart';

/// Habits in memory, answering like `/api/v1/habits`.
class FakeHabitsApi implements HabitsApi {
  final habits = <Map<String, dynamic>>[];
  final calls = <(String, String, Map<String, Object?>?)>[];
  int _next = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  Map<String, dynamic> seed(
    String name, {
    int color = 8,
    String kind = 'boolean',
    int num = 1,
    int den = 1,
    double target = 0,
    String unit = '',
    Map<String, double> entries = const {},
  }) {
    final habit = <String, dynamic>{
      'id': 'h${_next++}',
      'name': name,
      'question': '',
      'notes': '',
      'color': color,
      'kind': kind,
      'freq_num': num,
      'freq_den': den,
      'target_type': 'at_least',
      'target_value': target,
      'unit': unit,
      'sort_order': habits.length,
      'archived': false,
      'entries': <Map<String, dynamic>>[
        for (final e in entries.entries)
          {'day': e.key, 'value': e.value, 'skip': false},
      ],
    };
    habits.add(habit);
    return habit;
  }

  Map<String, dynamic> byId(String id) =>
      habits.firstWhere((h) => h['id'] == id);

  @override
  Future<Map<String, dynamic>> habitRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    calls.add((method, path, body));
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    final parts = Uri.parse(path).pathSegments.skip(3).toList();
    if (parts.isEmpty) {
      if (method == 'GET') return {'habits': habits};
      final habit = seed(body!['name'] as String);
      habit.addAll({...body}..remove('archived'));
      return {'habit': habit};
    }
    if (parts.first == 'reorder') {
      final ids = body!['habit_ids'] as List;
      habits.sort(
        (a, b) => ids.indexOf(a['id']).compareTo(ids.indexOf(b['id'])),
      );
      return {'reordered': true};
    }
    final habit = habits.where((h) => h['id'] == parts.first).firstOrNull;
    if (habit == null) throw const ApiException('پیدا نشد.', statusCode: 404);
    if (parts.length == 3) {
      final entries = (habit['entries'] as List).cast<Map<String, dynamic>>()
        ..removeWhere((e) => e['day'] == parts[2]);
      if (method == 'PUT') {
        final entry = {'day': parts[2], ...body!};
        entries.add(entry);
        return {'entry': entry};
      }
      return {'deleted': true};
    }
    if (method == 'DELETE') {
      habits.remove(habit);
      return {'deleted': true};
    }
    habit.addAll(body!);
    return {'habit': habit};
  }
}
