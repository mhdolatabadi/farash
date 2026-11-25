import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/features/projects/presentation/project_sidebar.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('selected Ledger navigation is legible and touch-friendly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SidebarTheme(
                child: SidebarRow(
                  selected: true,
                  child: ListTile(
                    selected: true,
                    leading: const Icon(Icons.today_outlined),
                    title: const Text('امروز'),
                    onTap: () => taps++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ListTile, 'امروز');
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      final decorated = find.descendant(
        of: find.byType(SidebarRow),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).border
                  is BorderDirectional,
        ),
      );
      expect(decorated, findsOneWidget);
      final decoration = tester.widget<DecoratedBox>(decorated).decoration;
      expect(decoration, isA<BoxDecoration>());
      final border = (decoration as BoxDecoration).border;
      expect(border, isA<BorderDirectional>());
      await tester.tap(row);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
