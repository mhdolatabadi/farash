import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:farash/core/calendar/calendar_settings.dart';

/// A reminder preference is opt-in for one account on one server, not a
/// global Android permission toggle. Never carry consent to another account.
class TaskDueNotificationPreference {
  TaskDueNotificationPreference({
    required String account,
    required String server,
    required CalendarSettingsStore store,
  }) : _store = store,
       _key =
           'task_due_notifications_v2_${sha256.convert(utf8.encode('$server|${account.trim().toLowerCase()}'))}';

  final CalendarSettingsStore _store;
  final String _key;

  Future<bool> read() async => await _store.read(_key) == 'on';

  Future<void> write(bool enabled) => _store.write(_key, enabled ? 'on' : 'off');
}
