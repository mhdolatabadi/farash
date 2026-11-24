import 'package:flutter/foundation.dart';
import 'package:menval/core/calendar/calendar_settings.dart';

/// One of the four Eisenhower quadrants. [important] and [urgent] say where
/// it sits, so a task dropped on it can be moved to match.
enum Quadrant {
  doFirst('فوری و مهم', important: true, urgent: true),
  schedule('مهم نه فوری', important: true, urgent: false),
  delegate('فوری نه مهم', important: false, urgent: true),
  later('نه فوری نه مهم', important: false, urgent: false);

  const Quadrant(this.title, {required this.important, required this.urgent});

  final String title;
  final bool important, urgent;

  /// By priority and due date: p1–p2 are important, late or due today is
  /// urgent. Written in the search query language, so it can be edited.
  String get defaultRule {
    final priority = important ? '(p1 | p2)' : '(p3 | p4)';
    return urgent
        ? '$priority & (overdue | today)'
        : '$priority & !(overdue | today)';
  }
}

/// Each quadrant's rule, kept on this device.
class MatrixRules extends ChangeNotifier {
  MatrixRules({CalendarSettingsStore? store}) : _store = store;

  final CalendarSettingsStore? _store;
  final _rules = <Quadrant, String>{};
  bool _disposed = false;

  static String _key(Quadrant q) => 'matrix_rule_${q.name}';

  String rule(Quadrant q) => _rules[q] ?? q.defaultRule;

  bool isDefault(Quadrant q) => !_rules.containsKey(q);

  Future<void> load() async {
    for (final q in Quadrant.values) {
      try {
        final saved = await _store?.read(_key(q));
        if (_disposed) return;
        if (saved != null && saved.trim().isNotEmpty) _rules[q] = saved;
      } catch (_) {
        // Unreadable storage keeps the default rule.
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// Sets [q]'s rule; an empty or default rule goes back to the default.
  Future<void> setRule(Quadrant q, String rule) async {
    final value = rule.trim();
    if (value.isEmpty || value == q.defaultRule) {
      _rules.remove(q);
    } else {
      _rules[q] = value;
    }
    notifyListeners();
    try {
      await _store?.write(_key(q), _rules[q] ?? '');
    } catch (_) {
      // The rule holds for this session.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
