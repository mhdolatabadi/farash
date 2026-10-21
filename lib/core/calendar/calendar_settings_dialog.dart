import 'package:flutter/material.dart';
import 'package:farash/core/settings/theme_preferences.dart';
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
      title: const Text('نمایش و تقویم'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ThemePreferencesScope.maybeOf(context)
              case final appearance?) ...[
            Text('نمایش', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<ThemeMode>(
              initialValue: appearance.mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'پوسته'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(
                    'همگام با دستگاه',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('روشن')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('تیره')),
              ],
              onChanged: (mode) {
                if (mode != null) appearance.setMode(mode);
              },
            ),
            const SizedBox(height: 24),
          ],
          RadioGroup<CalendarSystem>(
            groupValue: settings.system,
            onChanged: (system) {
              if (system != null) settings.setSystem(system);
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: CalendarSystem.jalali,
                  title: Text('خورشیدی'),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile(
                  value: CalendarSystem.gregorian,
                  title: Text('میلادی'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: settings.weekStart,
            isExpanded: true,
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
