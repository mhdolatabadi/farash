import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/calendar/jalali.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/task.dart';

/// Durations offered for a timed due, in minutes.
const durationChoices = [15, 30, 45, 60, 90, 120, 180, 240];

/// Opens the scheduler. Returns the chosen dates (possibly empty, for "no
/// date"), or null when it was cancelled. With [dueOnly] only the due date
/// is edited, as when rescheduling many tasks.
Future<TaskDates?> showDuePicker(
  BuildContext context, {
  required TaskDates initial,
  bool dueOnly = false,
  DateTime? now,
}) => showModalBottomSheet<TaskDates>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => DuePicker(initial: initial, dueOnly: dueOnly, now: now),
);

/// A short line for the dates, such as "فردا ۱۴:۰۰ · مهلت ۲۰ مهر".
String describeDates(
  TaskDates dates,
  CalendarSettings settings, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final due = dates.due;
  final parts = [
    if (due != null)
      [
        relativeDay(due.day, settings, today: today),
        if (due.isTimed) formatTime(due.localTime!),
        if (due.isTimed && dates.durationMinutes != null)
          '(${formatDuration(dates.durationMinutes!)})',
      ].join(' '),
    if (dates.deadline != null)
      'مهلت ${formatDate(parseDateKey(dates.deadline!), settings, today: today)}',
  ];
  return parts.isEmpty ? 'بدون تاریخ' : parts.join(' · ');
}

enum _Target { due, deadline }

class DuePicker extends StatefulWidget {
  const DuePicker({
    super.key,
    required this.initial,
    this.dueOnly = false,
    this.now,
  });

  final TaskDates initial;
  final bool dueOnly;
  final DateTime? now;

  @override
  State<DuePicker> createState() => _DuePickerState();
}

class _DuePickerState extends State<DuePicker> {
  late final DateTime _today = dayOf(widget.now ?? DateTime.now());
  late DateTime? _day = widget.initial.due?.day;
  late TimeOfDay? _time = widget.initial.due?.isTimed == true
      ? TimeOfDay.fromDateTime(widget.initial.due!.localTime!)
      : null;
  late int? _duration = widget.initial.durationMinutes;
  late DateTime? _deadline = widget.initial.deadline == null
      ? null
      : parseDateKey(widget.initial.deadline!);
  _Target _target = _Target.due;

  /// The month on show, as (year, month) in the active calendar.
  (int, int)? _month;

  DateTime? get _selected => _target == _Target.due ? _day : _deadline;

  void _select(DateTime? day) => setState(() {
    if (_target == _Target.due) {
      _day = day;
      if (day == null) {
        _time = null;
        _duration = null;
      }
    } else {
      _deadline = day;
    }
    if (day != null) _month = null;
  });

  (int, int) _monthOf(DateTime day, CalendarSettings settings) {
    if (!settings.isJalali) return (day.year, day.month);
    final j = JalaliDate.fromGregorian(day);
    return (j.year, j.month);
  }

  void _shiftMonth(int by, CalendarSettings settings) => setState(() {
    final (year, month) = _month ?? _monthOf(_selected ?? _today, settings);
    final index = year * 12 + (month - 1) + by;
    _month = (index ~/ 12, index % 12 + 1);
  });

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'ساعت انجام',
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _confirm() async {
    final navigator = Navigator.of(context);
    final initial = widget.initial;
    TaskDue? due;
    final day = _day;
    if (day != null) {
      final time = _time;
      if (time == null) {
        due = TaskDue.onDay(day);
      } else {
        final local = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        // An unchanged moment keeps the zone it was planned in.
        due = initial.due?.localTime == local
            ? initial.due
            : TaskDue.at(local, await deviceTimeZone());
      }
    }
    navigator.pop(
      TaskDates(
        due: due,
        deadline: widget.dueOnly
            ? initial.deadline
            : (_deadline == null ? null : dateKey(_deadline!)),
        durationMinutes: due?.isTimed == true
            ? (widget.dueOnly ? initial.durationMinutes : _duration)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = CalendarScope.of(context);
    final weekEnd = (settings.weekStart + 5) % 7 + 1;
    final thisWeekEnd = _today.add(
      Duration(days: (weekEnd - _today.weekday + 7) % 7),
    );
    final nextWeek = startOfWeek(
      _today,
      settings.weekStart,
    ).add(const Duration(days: 7));
    final quick = [
      ('امروز', _today),
      ('فردا', _today.add(const Duration(days: 1))),
      ('آخر هفته', thisWeekEnd),
      ('هفتهٔ بعد', nextWeek),
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.dueOnly ? 'تغییر تاریخ' : 'زمان‌بندی',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!widget.dueOnly) ...[
              SegmentedButton<_Target>(
                segments: const [
                  ButtonSegment(
                    value: _Target.due,
                    icon: Icon(Icons.event),
                    label: Text('تاریخ انجام'),
                  ),
                  ButtonSegment(
                    value: _Target.deadline,
                    icon: Icon(Icons.hourglass_bottom),
                    label: Text('مهلت'),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (s) => setState(() {
                  _target = s.single;
                  _month = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, day) in quick)
                  ChoiceChip(
                    label: Text(label),
                    tooltip: formatDate(
                      day,
                      settings,
                      today: _today,
                      withWeekday: true,
                    ),
                    selected: _selected == day,
                    onSelected: (_) => _select(day),
                  ),
                ChoiceChip(
                  label: Text(
                    _target == _Target.due ? 'بدون تاریخ' : 'بدون مهلت',
                  ),
                  selected: _selected == null,
                  onSelected: (_) => _select(null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MonthGrid(
              settings: settings,
              month: _month ?? _monthOf(_selected ?? _today, settings),
              today: _today,
              selected: _selected,
              onSelect: _select,
              onShift: (by) => _shiftMonth(by, settings),
            ),
            if (_target == _Target.due && _day != null) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: _time == null
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _pickTime,
                              icon: const Icon(Icons.schedule),
                              label: const Text('افزودن ساعت'),
                            ),
                          )
                        : Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule),
                                label: Text(
                                  'ساعت ${formatTime(DateTime(2000, 1, 1, _time!.hour, _time!.minute))}',
                                ),
                              ),
                              IconButton(
                                tooltip: 'حذف ساعت',
                                onPressed: () => setState(() {
                                  _time = null;
                                  _duration = null;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              if (_time != null && !widget.dueOnly)
                DropdownButtonFormField<int?>(
                  initialValue: _duration,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'مدت'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('بدون مدت'),
                    ),
                    for (final minutes in durationChoices)
                      DropdownMenuItem<int?>(
                        value: minutes,
                        child: Text(formatDuration(minutes)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _duration = value),
                ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('لغو'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _confirm, child: const Text('تأیید')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One month in the active calendar, weeks starting on the chosen day.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.settings,
    required this.month,
    required this.today,
    required this.selected,
    required this.onSelect,
    required this.onShift,
  });

  final CalendarSettings settings;
  final (int, int) month;
  final DateTime today;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (year, monthNumber) = month;
    final DateTime first;
    final int length;
    final String title;
    if (settings.isJalali) {
      first = JalaliDate(year, monthNumber, 1).toGregorian();
      length = JalaliDate.monthLength(year, monthNumber);
      title = '${jalaliMonths[monthNumber - 1]} ${persianDigits(year)}';
    } else {
      first = DateTime(year, monthNumber, 1);
      length = DateTime(year, monthNumber + 1, 0).day;
      title = '${gregorianMonths[monthNumber - 1]} ${persianDigits(year)}';
    }
    final leading = (first.weekday - settings.weekStart + 7) % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 0; d < length; d++)
        DateTime(first.year, first.month, first.day + d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'ماه قبل',
              onPressed: () => onShift(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'ماه بعد',
              onPressed: () => onShift(1),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdayInitials[(settings.weekStart - 1 + i) % 7],
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var row = 0; row < cells.length; row += 7)
          Row(
            children: [
              for (final day in cells.sublist(row, row + 7))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 48)
                      : _DayCell(
                          day: day,
                          label: settings.isJalali
                              ? JalaliDate.fromGregorian(day).day
                              : day.day,
                          isToday: day == today,
                          isSelected: day == selected,
                          semantics: formatDate(
                            day,
                            settings,
                            today: today,
                            withWeekday: true,
                            alwaysYear: true,
                          ),
                          onTap: () => onSelect(day),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.label,
    required this.isToday,
    required this.isSelected,
    required this.semantics,
    required this.onTap,
  });

  final DateTime day;
  final int label;
  final bool isToday;
  final bool isSelected;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: isSelected,
      label: semantics,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? scheme.primary : null,
                border: isToday && !isSelected
                    ? Border.all(color: scheme.primary)
                    : null,
              ),
              child: Text(
                persianDigits(label),
                style: TextStyle(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
