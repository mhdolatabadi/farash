import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/palette.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

import 'support/fake_tasks_api.dart';

const _work = Project(id: 'p1', name: 'کار', color: '#2563eb');

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('moshajjar palette', () {
    for (final brightness in Brightness.values) {
      test('text keeps 4.5:1 contrast ($brightness)', () {
        final theme = brightness == Brightness.dark
            ? FarashTheme.dark()
            : FarashTheme.light();
        final c = theme.colorScheme;
        for (final (name, fg) in [
          ('onSurface', c.onSurface),
          ('onSurfaceVariant', c.onSurfaceVariant),
          ('primary (today)', c.primary),
          ('tertiary (tomorrow)', c.tertiary),
          ('error (overdue)', c.error),
        ]) {
          expect(
            _contrast(fg, c.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name on surface',
          );
        }
        expect(_contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
      });
    }

    test('the theme and the glass read the same palette', () {
      final theme = FarashTheme.light();
      expect(theme.colorScheme.primary, const Color(0xFF8A5A12));
      expect(FarashTheme.dark().colorScheme.primary, const Color(0xFFE8B66B));
      // Pomegranate is kept for overdue alone.
      expect(theme.colorScheme.error, FarashPalette.moshajjar.light.overdue);
      expect(
        theme.extension<FarashGlassColors>()!.colors,
        FarashPalette.moshajjar.light,
      );
    });
  });

  group('motion', () {
    late FakeTasksApi api;
    setUp(() => api = FakeTasksApi());

    Future<void> pumpView(WidgetTester tester, {bool reduced = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: ProjectTasksView(
                  project: _work,
                  api: api,
                  token: () => 'token',
                  moveTargets: () => const [_work],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a completed row shows its check, then folds away', (
      tester,
    ) async {
      api.seed('p1', 'نوشتن گزارش');
      await pumpView(tester);

      await tester.tap(find.bySemanticsLabel('انجام «نوشتن گزارش»'));
      await tester.pump(const Duration(milliseconds: 80));
      // Still on screen and checked while it lingers; not yet sent.
      expect(find.text('نوشتن گزارش'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(api.byTitle('نوشتن گزارش').isCompleted, isFalse);

      await tester.pumpAndSettle();
      expect(find.text('نوشتن گزارش'), findsNothing);
      expect(api.byTitle('نوشتن گزارش').isCompleted, isTrue);
      expect(find.text('«نوشتن گزارش» انجام شد.'), findsOneWidget);
    });

    testWidgets('with reduced motion the row goes at once', (tester) async {
      api.seed('p1', 'نوشتن گزارش');
      await pumpView(tester, reduced: true);

      await tester.tap(find.bySemanticsLabel('انجام «نوشتن گزارش»'));
      await tester.pump();
      expect(api.byTitle('نوشتن گزارش').isCompleted, isTrue);
      await tester.pump();
      expect(find.text('نوشتن گزارش'), findsNothing);
    });

    testWidgets('a new task grows into the list', (tester) async {
      await pumpView(tester);
      await tester.enterText(find.byType(TextField), 'تازه');
      await tester.tap(find.byTooltip('افزودن کار'));
      // The row appears, starts growing on the next frame, and is midway
      // a little later.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The row starts at no height, so look offstage too.
      SizeTransition growth() => tester.widget<SizeTransition>(
        find
            .ancestor(
              of: find.text('تازه', skipOffstage: false),
              matching: find.byType(SizeTransition, skipOffstage: false),
            )
            .first,
      );
      expect(growth().sizeFactor.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(growth().sizeFactor.value, 1);
    });
  });
}
