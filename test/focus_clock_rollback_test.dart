import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/focus/focus_controller.dart';

void main() {
  test('backward clock changes cannot extend a running focus session', () {
    var now = DateTime(2026, 11, 22, 10);
    final focus = FocusController(now: () => now);
    addTearDown(focus.dispose);

    focus.choose(5);
    focus.start();
    now = now.subtract(const Duration(minutes: 30));
    focus.refresh();

    expect(focus.running, isTrue);
    expect(focus.remaining, const Duration(minutes: 5));
    expect(focus.progress, 0);

    now = DateTime(2026, 11, 22, 10, 6);
    focus.refresh();
    expect(focus.remaining, Duration.zero);
    expect(focus.finished, isTrue);
    expect(focus.progress, 1);
  });
}
