import 'package:menval/core/calendar/calendar_month.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/calendar/jalali.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:flutter/material.dart';

/// A provider-independent, owner-scoped task month view.
class TaskMonthView extends StatefulWidget {
  const TaskMonthView({
    super.key,
    required this.loadTasks,
    this.now,
    this.onOpenTask,
  });

  final Future<List<Task>> Function(DateTime from, DateTime to) loadTasks;
  final DateTime Function()? now;
  final ValueChanged<Task>? onOpenTask;

  @override
  State<TaskMonthView> createState() => _TaskMonthViewState();
}

class _TaskMonthViewState extends State<TaskMonthView> {
  late DateTime _selected = dayOf((widget.now ?? DateTime.now)());
  List<Task> _tasks = const [];
  Object? _error;
  bool _loading = true;
  int _generation = 0;
  DateTime? _loadedGridStart;
  DateTime? _loadedGridEnd;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final month = monthContaining(_selected, CalendarScope.of(context));
    if (_loadedGridStart != month.gridStart ||
        _loadedGridEnd != month.gridEnd) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant TaskMonthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new loader may represent another signed-in owner. Never retain the
    // previous owner's task data or accept their pending response.
    if (oldWidget.loadTasks != widget.loadTasks) _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final month = monthContaining(_selected, CalendarScope.of(context));
    _loadedGridStart = month.gridStart;
    _loadedGridEnd = month.gridEnd;
    setState(() {
      _loading = true;
      _error = null;
      _tasks = const [];
    });
    try {
      final tasks = await widget.loadTasks(month.gridStart, month.gridEnd);
      if (!mounted || generation != _generation) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectDay(DateTime day) {
    final settings = CalendarScope.of(context);
    final previousMonth = monthContaining(_selected, settings).firstDay;
    final targetMonth = monthContaining(day, settings).firstDay;
    setState(() => _selected = dayOf(day));
    // Adjacent-month cells must navigate and fetch the new month rather
    // than leave the old header and stale data visible.
    if (targetMonth != previousMonth) _load();
  }

  void _move(int months) {
    setState(() {
      _selected = shiftCalendarMonth(
        _selected,
        months,
        CalendarScope.of(context),
      );
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = CalendarScope.of(context);
    final month = monthContaining(_selected, settings);
    final theme = Theme.of(context);
    final today = dayOf((widget.now ?? DateTime.now)());
    final counts = <DateTime, int>{};
    for (final task in _tasks) {
      final due = task.due;
      if (due == null || task.isCompleted) continue;
      final date = dayOf(due.day);
      counts[date] = (counts[date] ?? 0) + 1;
    }
    final selectedTasks = [
      for (final task in _tasks)
        if (task.due != null && daysBetween(task.due!.day, _selected) == 0)
          task,
    ];
    final currentMonth = settings.isJalali
        ? JalaliDate.fromGregorian(_selected).month
        : _selected.month;
    final year = settings.isJalali
        ? JalaliDate.fromGregorian(_selected).year
        : _selected.year;
    final monthName = settings.isJalali
        ? jalaliMonths[currentMonth - 1]
        : gregorianMonths[currentMonth - 1];
    final weekdayHeaders = [
      for (var i = 0; i < 7; i++)
        weekdayInitials[(settings.weekStart - 1 + i) % 7],
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'ماه قبل',
              onPressed: () => _move(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Expanded(
              child: Text(
                '$monthName ${persianDigits('$year')}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'ماه بعد',
              onPressed: () => _move(1),
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selected = dayOf((widget.now ?? DateTime.now)());
                });
                _load();
              },
              child: const Text('امروز'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final label in weekdayHeaders)
              Expanded(
                child: Center(
                  child: Text(label, style: theme.textTheme.labelMedium),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < month.days.length ~/ 7; row++)
          Row(
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final day = month.days[row * 7 + column];
                      final sameMonth =
                          !day.isBefore(month.firstDay) &&
                          !day.isAfter(month.lastDay);
                      final selected = daysBetween(day, _selected) == 0;
                      final isToday = daysBetween(day, today) == 0;
                      final dayNumber = settings.isJalali
                          ? JalaliDate.fromGregorian(day).day
                          : day.day;
                      return Padding(
                        padding: const EdgeInsets.all(2),
                        child: Semantics(
                          label:
                              '${formatDate(day, settings, withWeekday: true)}'
                              '${isToday ? '، امروز' : ''}، '
                              '${persianDigits('${counts[day] ?? 0}')} کار باز',
                          button: true,
                          selected: selected,
                          onTap: () => _selectDay(day),
                          excludeSemantics: true,
                          child: InkWell(
                            key: ValueKey(
                              'month-day-${day.year}-${day.month}-${day.day}',
                            ),
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _selectDay(day),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 56),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: selected
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                                border: isToday
                                    ? Border.all(
                                        color: theme.colorScheme.primary,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Text(
                                    persianDigits('$dayNumber'),
                                    style: TextStyle(
                                      color: sameMonth
                                          ? null
                                          : theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if ((counts[day] ?? 0) > 0)
                                    Text(
                                      persianDigits('${counts[day]}'),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Text(
          formatDate(_selected, settings, withWeekday: true),
          style: theme.textTheme.titleMedium,
        ),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          Column(
            children: [
              const Text('دریافت کارهای تقویم ممکن نشد.'),
              TextButton(onPressed: _load, child: const Text('تلاش دوباره')),
            ],
          )
        else if (selectedTasks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('برای این روز کاری زمان‌بندی نشده است.'),
          )
        else
          for (final task in selectedTasks)
            ListTile(
              key: ValueKey('month-task-${task.id}'),
              onTap: widget.onOpenTask == null
                  ? null
                  : () => widget.onOpenTask!(task),
              title: Text(task.title),
              leading: Icon(
                task.isCompleted
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
            ),
      ],
    );
  }
}
