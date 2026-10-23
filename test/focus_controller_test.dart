import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/focus/focus_controller.dart';

void main() {
  test(
    'deadline catches suspended ticks and pause preserves remaining time',
    () {
      var now = DateTime(2026, 10, 15);
      final timer = FocusController(now: () => now);
      addTearDown(timer.dispose);
      timer.start();
      now = now.add(const Duration(minutes: 8));
      timer.refresh();
      expect(timer.remaining, const Duration(minutes: 17));
      timer.pause();
      now = now.add(const Duration(hours: 2));
      timer.refresh();
      expect(timer.remaining, const Duration(minutes: 17));
      timer.start();
      now = now.add(const Duration(minutes: 18));
      timer.refresh();
      expect(timer.remaining, Duration.zero);
      expect(timer.finished, isTrue);
      expect(timer.running, isFalse);
    },
  );
  test('running sessions refuse mode changes and reset clears completion', () {
    var now = DateTime(2026);
    final timer = FocusController(now: () => now);
    addTearDown(timer.dispose);
    timer.choose(5);
    timer.start();
    timer.choose(15);
    expect(timer.minutes, 5);
    now = now.add(const Duration(minutes: 5));
    timer.refresh();
    expect(timer.finished, isTrue);
    timer.reset();
    expect(timer.finished, isFalse);
    expect(timer.remaining, const Duration(minutes: 5));
  });

  test('progress follows elapsed time, including suspension', () {
    final origin = DateTime(2026);
    var now = origin;
    final timer = FocusController(now: () => now);
    addTearDown(timer.dispose);
    expect(timer.progress, 0);
    timer.start();
    now = origin.add(const Duration(minutes: 10));
    timer.refresh();
    expect(timer.progress, closeTo(0.4, 1e-9));
    timer.pause();
    now = now.add(const Duration(hours: 2));
    timer.refresh();
    expect(timer.progress, closeTo(0.4, 1e-9));
    timer.start();
    now = now.add(const Duration(minutes: 15));
    timer.refresh();
    expect(timer.finished, isTrue);
    expect(timer.progress, 1);
    timer.reset();
    expect(timer.progress, 0);
    timer.choose(5);
    timer.start();
    now = now.add(const Duration(minutes: 1));
    timer.refresh();
    expect(timer.progress, closeTo(0.2, 1e-9));
  });

  test('restored remaining time stays within the selected duration', () {
    final timer = FocusController();
    addTearDown(timer.dispose);
    timer.restoreRemaining(const Duration(hours: 1));
    expect(timer.remaining, const Duration(minutes: 25));
    expect(timer.progress, 0);
    timer.restoreRemaining(const Duration(seconds: -1));
    expect(timer.remaining, Duration.zero);
    expect(timer.progress, 1);
    timer.start();
    timer.restoreRemaining(const Duration(minutes: 10));
    expect(timer.remaining, const Duration(minutes: 25));
    expect(timer.progress, 0);
  });
}
