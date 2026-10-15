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
}
