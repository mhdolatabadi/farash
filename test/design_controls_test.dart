import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/app/controls.dart';
import 'package:menval/app/press_depth.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: MenvalTheme.light(),
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(child: child),
      ),
    ),
  );

  testWidgets('checkbox has a compact mark and one accessible 48px target', (
    tester,
  ) async {
    var checked = false;
    var changes = 0;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => MenvalCheckbox(
            value: checked,
            label: 'تکمیل مطالعه',
            onChanged: (value) => setState(() {
              checked = value;
              changes++;
            }),
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    final mark = find
        .descendant(
          of: find.byType(MenvalCheckbox),
          matching: find.byType(AnimatedContainer),
        )
        .last;
    expect(tester.getSize(mark), const Size(20, 20));
    expect(
      tester.getSemantics(find.bySemanticsLabel('تکمیل مطالعه')),
      matchesSemantics(
        label: 'تکمیل مطالعه',
        hasCheckedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    await tester.tapAt(
      tester.getTopLeft(find.byType(IconButton)) + const Offset(4, 24),
    );
    await tester.pumpAndSettle();
    expect(checked, isTrue);
    expect(changes, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('تکمیل مطالعه')),
      matchesSemantics(
        label: 'تکمیل مطالعه',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('keyboard focus and activation reach the same icon action', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        MenvalIconButton(
          tooltip: 'افزودن کار',
          icon: Icons.add,
          onPressed: () => activations++,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.statesController!.value, contains(WidgetState.focused));
    expect(
      button.style!.side!.resolve(button.statesController!.value)!.width,
      2,
    );
    expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(activations, 1);
  });

  testWidgets('pressed action is inset and disabling clears its depth', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    var enabled = true;
    late StateSetter change;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            change = setState;
            return PressDepth(
              enabled: enabled,
              statesController: states,
              child: const SizedBox(width: 48, height: 48),
            );
          },
        ),
      ),
    );
    states.update(WidgetState.pressed, true);
    await tester.pumpAndSettle();
    bool paintsInset(CustomPaint paint) =>
        paint.foregroundPainter is MenvalInsetPainter;
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && paintsInset(w)),
      findsOneWidget,
    );
    change(() => enabled = false);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && paintsInset(w)),
      findsNothing,
    );
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('disabled checkbox exposes its state without an action', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MenvalCheckbox(value: true, label: 'مطالعه ثبت‌شده')),
    );
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    expect(
      tester.getSemantics(find.bySemanticsLabel('مطالعه ثبت‌شده')),
      matchesSemantics(
        label: 'مطالعه ثبت‌شده',
        hasCheckedState: true,
        isChecked: true,
        hasEnabledState: true,
      ),
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
  });
}
