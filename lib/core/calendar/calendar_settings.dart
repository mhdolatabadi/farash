import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum CalendarSystem { jalali, gregorian }

/// How dates read on this device: the calendar and the first day of the
/// week. Account-wide settings come with #25.
class CalendarSettings extends ChangeNotifier {
  CalendarSettings({
    CalendarSettingsStore? store,
    CalendarSystem system = CalendarSystem.jalali,
    int weekStart = DateTime.saturday,
  }) : _store = store,
       _system = system,
       _weekStart = weekStart;

  final CalendarSettingsStore? _store;
  CalendarSystem _system;
  int _weekStart;

  CalendarSystem get system => _system;
  bool get isJalali => _system == CalendarSystem.jalali;

  /// DateTime.monday … DateTime.sunday; Saturday by default.
  int get weekStart => _weekStart;

  Future<void> load() async {
    final store = _store;
    if (store == null) return;
    try {
      final system = await store.read('calendar');
      final weekStart = int.tryParse(await store.read('week_start') ?? '');
      _system =
          CalendarSystem.values.where((s) => s.name == system).firstOrNull ??
          _system;
      if (weekStart != null && weekStart >= 1 && weekStart <= 7) {
        _weekStart = weekStart;
      }
      notifyListeners();
    } catch (_) {
      // Unreadable storage keeps the defaults.
    }
  }

  Future<void> setSystem(CalendarSystem system) async {
    if (system == _system) return;
    _system = system;
    notifyListeners();
    await _save('calendar', system.name);
  }

  Future<void> setWeekStart(int weekday) async {
    if (weekday == _weekStart || weekday < 1 || weekday > 7) return;
    _weekStart = weekday;
    notifyListeners();
    await _save('week_start', '$weekday');
  }

  Future<void> _save(String key, String value) async {
    try {
      await _store?.write(key, value);
    } catch (_) {
      // The choice still applies for this session.
    }
  }
}

abstract interface class CalendarSettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// The same per-device storage the session token uses.
class SecureCalendarSettingsStore implements CalendarSettingsStore {
  SecureCalendarSettingsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: 'farash.$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'farash.$key', value: value);
}

class MemoryCalendarSettingsStore implements CalendarSettingsStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
