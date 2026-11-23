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
  DateTime? get deadline => _deadline;
  Duration get remaining => _remaining;

  /// How much of the session has elapsed, 0 to 1, for the progress ring.
  double get progress {
    final total = Duration(minutes: minutes).inMilliseconds;
    final elapsed = (total - _remaining.inMilliseconds).clamp(0, total);
    return elapsed / total;
  }

  void choose(int value) {
    if (running || ![5, 15, 25].contains(value)) return;
    minutes = value;
    reset();
  }

  void restoreRemaining(Duration value) {
    if (running) return;
    final total = Duration(minutes: minutes).inMilliseconds;
    _remaining = Duration(milliseconds: value.inMilliseconds.clamp(0, total));
    finished = false;
    notifyListeners();
  }

  /// Restore a session after process restart. A running deadline is always
  /// evaluated against the wall clock; a paused session never advances.
  void restoreState({
    required int mode,
    required Duration remaining,
    DateTime? deadline,
    String? title,
    bool wasFinished = false,
  }) {
    if (running || !const [5, 15, 25].contains(mode)) return;
    _ticker?.cancel();
    minutes = mode;
    taskTitle = title;
    final total = Duration(minutes: mode).inMilliseconds;
    _remaining = Duration(
      milliseconds: remaining.inMilliseconds.clamp(0, total),
    );
    _deadline = null;
    finished = wasFinished && _remaining == Duration.zero;
    if (deadline != null) {
      final left = deadline.difference(_now());
      if (left <= Duration.zero) {
        _remaining = Duration.zero;
        finished = true;
      } else {
        _remaining = Duration(
          milliseconds: left.inMilliseconds.clamp(0, total),
        );
        // A restored deadline may be far in the future after a device clock
        // rollback. Bound both the displayed time and the active deadline.
        _deadline = _now().add(_remaining);
        finished = false;
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
      }
    }
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
    final total = Duration(minutes: minutes);
    _remaining = left.isNegative
        ? Duration.zero
        : left > total
        ? total
        : left;
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
