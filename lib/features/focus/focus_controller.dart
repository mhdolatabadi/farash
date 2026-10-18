import 'dart:async';
import 'package:flutter/foundation.dart';

/// Kept in the signed-in shell, so navigation preserves a session and
/// signing out disposes it. A deadline catches up after suspended ticks.
class FocusController extends ChangeNotifier {
  FocusController({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  Timer? _ticker;
  DateTime? _deadline;
  Duration _remaining = const Duration(minutes: 25);
  int minutes = 25;
  bool finished = false;
  String? taskTitle;
  bool get running => _deadline != null;
  Duration get remaining => _remaining;
  void choose(int value) {
    if (running || ![5, 15, 25].contains(value)) return;
    minutes = value;
    reset();
  }

  void restoreRemaining(Duration value) {
    if (running) return;
    _remaining = value.isNegative ? Duration.zero : value;
    finished = false;
    notifyListeners();
  }

  void start() {
    if (running) return;
    if (_remaining == Duration.zero) _remaining = Duration(minutes: minutes);
    finished = false;
    _deadline = _now().add(_remaining);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    notifyListeners();
  }

  void refresh() {
    final deadline = _deadline;
    if (deadline == null) return;
    final left = deadline.difference(_now());
    _remaining = left.isNegative ? Duration.zero : left;
    if (_remaining == Duration.zero) {
      _deadline = null;
      _ticker?.cancel();
      finished = true;
    }
    notifyListeners();
  }

  void pause() {
    refresh();
    _deadline = null;
    _ticker?.cancel();
    notifyListeners();
  }

  void reset() {
    _ticker?.cancel();
    _deadline = null;
    _remaining = Duration(minutes: minutes);
    finished = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
