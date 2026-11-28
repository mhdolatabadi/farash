import 'package:menval/core/api/api_client.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';

class FakeCalendarEventsApi implements CalendarEventsApi {
  final rows = <Map<String, dynamic>>[];
  final requests = <String, Map<String, dynamic>>{};
  final calls = <(String, String, Map<String, Object?>?)>[];
  Object? failNext;
  bool loseCreateResponse = false;
  int _serial = 0;

  @override
  Future<Map<String, dynamic>> eventRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    calls.add((method, path, body));
    if (failNext case final failure?) {
      failNext = null;
      throw failure;
    }
    final uri = Uri.parse(path);
    if (method == 'GET') {
      final from = DateTime.parse(uri.queryParameters['from']!);
      final to = DateTime.parse(uri.queryParameters['to']!);
      return {
        'events': [
          for (final row in rows)
            if (row['deleted'] != true &&
                DateTime.parse(row['start_at'] as String).isBefore(to) &&
                DateTime.parse(row['end_at'] as String).isAfter(from))
              Map<String, dynamic>.from(row),
        ],
      };
    }
    if (method == 'POST' && uri.path == '/api/v1/events') {
      final key = body!['request_key'] as String;
      final event = requests.putIfAbsent('$token:$key', () {
        final row = <String, dynamic>{
          ...body,
          'id': 'event-${++_serial}',
          'version': 1,
        };
        rows.add(row);
        return Map<String, dynamic>.from(row);
      });
      if (loseCreateResponse) {
        loseCreateResponse = false;
        throw const ApiException('Lost response');
      }
      return {'event': Map<String, dynamic>.from(event)};
    }
    final id = uri.pathSegments[3];
    final row = rows.singleWhere((row) => row['id'] == id);
    if (method == 'PATCH') {
      if (body!['version'] != row['version']) {
        throw const ApiException('Conflict', code: 'calendar_event_conflict');
      }
      row.addAll(body);
    } else {
      row['deleted'] = method == 'DELETE';
    }
    row['version'] = (row['version'] as int) + 1;
    return {'event': Map<String, dynamic>.from(row)};
  }
}
