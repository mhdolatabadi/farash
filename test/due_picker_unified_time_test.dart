import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/due_picker.dart';

void main() {
  testWidgets('date and precise time are edited in the same sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScope(
          settings: CalendarSettings(),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDuePicker(
                  context,
                  initial: const TaskDates(),
                  now: DateTime(2026, 11, 25),
                ),
                child: const Text('باز کردن'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();
    expect(find.text('تاریخ و ساعت'), findsOneWidget);
    expect(find.byType(DuePicker), findsOneWidget);

    await tester.tap(find.text('امروز'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن ساعت'));
    await tester.pumpAndSettle();

    expect(find.byType(DuePicker), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.text('حذف ساعت'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
