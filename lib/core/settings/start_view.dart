import 'package:flutter/foundation.dart';
import 'package:farash/core/calendar/calendar_settings.dart';

/// Which list opens when the app starts on this device: the Inbox
/// (`inbox`) or a view across projects, by its name.
class StartView extends ChangeNotifier {
  StartView({CalendarSettingsStore? store, String value = inbox})
    : _store = store,
      _value = value;

  static const inbox = 'inbox';
  static const _key = 'start_view';

  final CalendarSettingsStore? _store;
  String _value;
  bool _loaded = false;

  String get value => _value;

  /// Whether the saved choice has been read; until then [value] is the
  /// default.
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final saved = await _store?.read(_key);
      if (saved != null && saved.isNotEmpty) _value = saved;
    } catch (_) {
      // Unreadable storage keeps the Inbox.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> set(String value) async {
    if (value == _value) return;
    _value = value;
    notifyListeners();
    try {
      await _store?.write(_key, value);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}
