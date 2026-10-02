import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';

/// Picks the calendar and the first day of the week for this device.
Future<void> showCalendarSettings(
  BuildContext context,
  CalendarSettings settings,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => AlertDialog(
      title: const Text('تقویم'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<CalendarSystem>(
            segments: const [
              ButtonSegment(
                value: CalendarSystem.jalali,
                label: Text('خورشیدی'),
              ),
              ButtonSegment(
                value: CalendarSystem.gregorian,
                label: Text('میلادی'),
              ),
            ],
            selected: {settings.system},
            onSelectionChanged: (s) => settings.setSystem(s.single),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: settings.weekStart,
            decoration: const InputDecoration(labelText: 'شروع هفته'),
            items: [
              for (final day in const [
                DateTime.saturday,
                DateTime.sunday,
                DateTime.monday,
              ])
                DropdownMenuItem(
                  value: day,
                  child: Text(weekdayNames[day - 1]),
                ),
            ],
            onChanged: (day) {
              if (day != null) settings.setWeekStart(day);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('بستن'),
        ),
      ],
    ),
  ),
);
