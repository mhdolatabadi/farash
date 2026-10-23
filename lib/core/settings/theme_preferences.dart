import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_settings.dart';

/// Device appearance; unrelated to account data and safe to retain on logout.
class ThemePreferences extends ChangeNotifier {
  ThemePreferences({
    CalendarSettingsStore? store,
    ThemeMode mode = ThemeMode.system,
  }) : _store = store,
       _mode = mode;

  static const _key = 'theme_mode';
  final CalendarSettingsStore? _store;
  ThemeMode _mode;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _writes = Future.value();

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await _store?.read(_key);
      if (_disposed || revision != _revision) return;
      _mode =
          ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
          _mode;
      notifyListeners();
    } catch (_) {
      // Unreadable storage keeps the default.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_disposed) return;
    _revision++;
    if (mode != _mode) {
      _mode = mode;
      notifyListeners();
    }
    _writes = _writes.then((_) async {
      try {
        await _store?.write(_key, mode.name);
      } catch (_) {
        // The session choice remains; selecting it again retries storage.
      }
    });
    await _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ThemePreferencesScope extends InheritedNotifier<ThemePreferences> {
  const ThemePreferencesScope({
    super.key,
    required ThemePreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static ThemePreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ThemePreferencesScope>()
      ?.notifier;
}
