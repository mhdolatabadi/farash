import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/press_depth.dart';

void main() {
  testWidgets('plastic surface depresses and returns without stealing taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressDepth(
              child: Material(
                child: InkWell(
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 160,
                    height: 56,
                    child: Center(child: Text('کار جدید')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final target = find.text('کار جدید');
    final gesture = await tester.startGesture(tester.getCenter(target));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.975);

    await gesture.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(taps, 1);
  });

  testWidgets('drag cancels pressed styling for scroll gestures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressDepth(
            child: InkWell(
              onTap: () {},
              child: const SizedBox(width: 220, height: 100),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(30, 30));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.975);
    await gesture.moveBy(const Offset(0, 28));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
  });

  testWidgets('respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PressDepth(child: SizedBox(width: 80, height: 60)),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(30, 30));
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
    await gesture.up();
  });
}
