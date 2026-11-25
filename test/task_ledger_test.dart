import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/task_tile.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('Ledger task rows keep titles readable in narrow large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MenvalTheme.dark() : MenvalTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: TaskTile(
              task: const Task(
                id: 'ledger-task',
                projectId: 'inbox',
                title: 'نوشتن یادداشت‌های طراحی منوال',
              ),
              onToggle: () {},
              onOpen: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(
        find.text('نوشتن یادداشت‌های طراحی منوال'),
      );
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(find.byType(TaskTile), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('نوشتن یادداشت‌های طراحی منوال'));
      expect(opened, isTrue);
    });
  }
}
