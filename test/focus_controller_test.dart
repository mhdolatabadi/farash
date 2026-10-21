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

  test(
    'every weaving boundary is elapsed-time based, including suspension',
    () {
      final origin = DateTime(2026);
      var now = origin;
      final timer = FocusController(now: () => now);
      addTearDown(timer.dispose);
      expect(timer.weavingFrame, 0);
      timer.start();
      for (var frame = 1; frame <= 9; frame++) {
        final boundary = (1500000 * frame + 8) ~/ 9;
        now = origin.add(Duration(milliseconds: boundary - 1));
        timer.refresh();
        expect(timer.weavingFrame, frame - 1);
        now = origin.add(Duration(milliseconds: boundary));
        timer.refresh();
        expect(timer.weavingFrame, frame);
      }
      expect(timer.finished, isTrue);
      now = now.add(const Duration(hours: 2));
      timer.refresh();
      expect(timer.weavingFrame, 9);
      timer.start();
      expect(timer.weavingFrame, 0);
      expect(timer.design, 1);
    },
  );

  test('pause, resume and reset preserve the intended weaving state', () {
    var now = DateTime(2026);
    final timer = FocusController(now: () => now);
    addTearDown(timer.dispose);
    timer.start();
    now = now.add(const Duration(minutes: 10));
    timer.pause();
    expect(timer.weavingFrame, 3);
    now = now.add(const Duration(hours: 2));
    timer.refresh();
    expect(timer.weavingFrame, 3);
    timer.start();
    now = now.add(const Duration(minutes: 5));
    timer.refresh();
    expect(timer.weavingFrame, 5);
    timer.reset();
    expect(timer.weavingFrame, 0);
    expect(timer.design, 0);
    for (final minutes in [5, 15]) {
      timer.choose(minutes);
      timer.start();
      now = now.add(Duration(minutes: minutes));
      timer.refresh();
      expect(timer.finished, isTrue);
      expect(timer.weavingFrame, 0);
      timer.start();
      expect(timer.design, 0);
      timer.reset();
    }
  });

  test('restored remaining time stays within the selected duration', () {
    final timer = FocusController();
    addTearDown(timer.dispose);
    timer.restoreRemaining(const Duration(hours: 1));
    expect(timer.remaining, const Duration(minutes: 25));
    expect(timer.weavingFrame, 0);
    timer.restoreRemaining(const Duration(seconds: -1));
    expect(timer.remaining, Duration.zero);
    expect(timer.weavingFrame, 9);
    timer.start();
    timer.restoreRemaining(const Duration(minutes: 10));
    expect(timer.remaining, const Duration(minutes: 25));
    expect(timer.weavingFrame, 0);
  });
}
