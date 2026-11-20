import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:farash/core/calendar/calendar_settings.dart';

/// A wall-clock snapshot, not an authoritative work-time entry or reward.
class FocusSessionData {
  const FocusSessionData({
    required this.minutes,
    required this.remainingMs,
    this.deadlineMs,
    this.taskTitle,
    this.taskId,
    this.entryId,
    this.finished = false,
  });

  final int minutes;
  final int remainingMs;
  final int? deadlineMs;
  final String? taskTitle;
  final String? taskId;
  final String? entryId;
  final bool finished;

  String encode() => jsonEncode({
    'version': 1,
    'minutes': minutes,
    'remaining_ms': remainingMs,
    'deadline_ms': deadlineMs,
    'task_title': taskTitle,
    'task_id': taskId,
    'entry_id': entryId,
    'finished': finished,
  });

  static FocusSessionData? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return null;
      }
      final minutes = decoded['minutes'];
      final remaining = decoded['remaining_ms'];
      final deadline = decoded['deadline_ms'];
      if (minutes is! int ||
          !const [5, 15, 25].contains(minutes) ||
          remaining is! int ||
          remaining < 0 ||
          remaining > minutes * 60000 ||
          (deadline != null && (deadline is! int || deadline < 0))) {
        return null;
      }
      String? optionalText(String key) {
        final v = decoded[key];
        return v is String && v.length <= 500 && v.isNotEmpty ? v : null;
      }

      return FocusSessionData(
        minutes: minutes,
        remainingMs: remaining,
        deadlineMs: deadline as int?,
        taskTitle: optionalText('task_title'),
        taskId: optionalText('task_id'),
        entryId: optionalText('entry_id'),
        finished: decoded['finished'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Isolated by account and API origin; clear it explicitly at sign-out.
class FocusSessionStorage {
  FocusSessionStorage({
    required String account,
    required String server,
    CalendarSettingsStore? store,
  }) : _store = store ?? SecureCalendarSettingsStore(),
       _key =
           'focus_v1_${sha256.convert(utf8.encode('$server|${account.trim().toLowerCase()}'))}';

  final CalendarSettingsStore _store;
  final String _key;

  Future<FocusSessionData?> read() async {
    try {
      return FocusSessionData.decode(await _store.read(_key));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(FocusSessionData? session) =>
      _store.write(_key, session?.encode() ?? '');
}
