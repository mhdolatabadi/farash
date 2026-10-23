import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';

/// Structured server schedule. Dates remain civil ISO keys; selectors are
/// interpreted by the server in the explicitly stored IANA time zone.
class RecurrenceState {
  RecurrenceState.fromJson(Map<String, dynamic> json)
    : schedule = Map<String, dynamic>.from(json['schedule'] as Map),
      emitted = json['emitted'] as int,
      advanced = json['advanced_at'] != null,
      nextTaskId = json['next_task_id'] as String?;

  final Map<String, dynamic> schedule;
  final int emitted;
  final bool advanced;
  final String? nextTaskId;
  Map<String, dynamic> get rule =>
      Map<String, dynamic>.from(schedule['rule'] as Map);
}

class RecurrenceService {
  RecurrenceService(this.transport, this.token);
  final TimeApi transport;
  final String? Function() token;

  String _token() =>
      token() ??
      (throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.'));
  String _path(String id) =>
      '/api/v1/tasks/${Uri.encodeComponent(id)}/recurrence';

  Future<RecurrenceState?> load(String id) async =>
      _state(await transport.timeRequest(_token(), 'GET', _path(id)));

  Future<RecurrenceState?> save(
    String id,
    Map<String, Object?>? schedule,
  ) async => _state(
    await transport.timeRequest(
      _token(),
      'PUT',
      _path(id),
      body: {'schedule': schedule},
    ),
  );

  Future<void> skip(String id) async {
    await transport.timeRequest(_token(), 'POST', '${_path(id)}/skip');
  }

  Future<void> undo(String id) async {
    await transport.timeRequest(_token(), 'POST', '${_path(id)}/undo');
  }

  static RecurrenceState? _state(Map<String, dynamic> body) =>
      body['recurrence'] == null
      ? null
      : RecurrenceState.fromJson(body['recurrence'] as Map<String, dynamic>);
}
