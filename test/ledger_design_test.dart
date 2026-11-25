import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/surfaces.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final light = first > second ? first : second;
  final dark = first > second ? second : first;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  test('Ledger palette keeps body and action text legible in both modes', () {
    for (final theme in [MenvalTheme.light(), MenvalTheme.dark()]) {
      final colors = theme.colorScheme;
      expect(contrast(colors.onSurface, colors.surface), greaterThan(4.5));
      expect(contrast(colors.onPrimary, colors.primary), greaterThan(4.5));
      expect(
        contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThan(4.5),
      );
      expect(
        contrast(colors.onSurfaceVariant, colors.surface),
        greaterThan(4.5),
      );
    }
    expect(MenvalTheme.palette.name, 'ledger');
  });

  for (final dark in [false, true]) {
    testWidgets('Ledger signet and quiet surfaces work at 320px and 2x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 740),
              textScaler: TextScaler.linear(2),
            ),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        MenvalMark(size: 48),
                        SoftTile(child: Text('برنامهٔ امروز')),
                        SoftWell(child: Text('فهرست کارها')),
                        Panel(child: Text('جزئیات')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('م'), findsOneWidget);
      expect(find.text('برنامهٔ امروز'), findsOneWidget);
      expect(find.text('فهرست کارها'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
