import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter/material.dart';

typedef CalendarTaskLoader = Future<List<Task>> Function(
  DateTime from,
  DateTime to,
);

/// A native Farash calendar. External providers are optional overlays.
class TaskCalendarView extends StatefulWidget {
  const TaskCalendarView({
    super.key,
    required this.loadTasks,
    this.now,
  });

  final CalendarTaskLoader loadTasks;
  final DateTime Function()? now;

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  late DateTime _selected = dayOf((widget.now ?? DateTime.now)());
  List<Task> _tasks = const [];
  bool _loading = true;
  Object? _error;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_generation == 0) _load();
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  DateTime get _start =>
      startOfWeek(_selected, CalendarScope.of(context).weekStart);

  Future<void> _load() async {
    final generation = ++_generation;
    final start = _start;
    setState(() {
      _loading = true;
      _error = null;
      _tasks = const [];
    });
    try {
      final tasks = await widget.loadTasks(
        start,
        DateTime(start.year, start.month, start.day + 6),
      );
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

  void _shiftWeek(int offset) {
    setState(() {
      _selected = DateTime(
        _selected.year,
        _selected.month,
        _selected.day + offset * 7,
      );
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final settings = CalendarScope.of(context);
    final theme = Theme.of(context);
    final start = _start;
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final selectedTasks = [
      for (final task in _tasks)
        if (task.due != null &&
            daysBetween(task.due!.day, _selected) == 0)
          task,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('تقویم')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'هفتهٔ قبل',
                      onPressed: () => _shiftWeek(-1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    Expanded(
                      child: Text(
                        '${formatDate(days.first, settings)} تا ${formatDate(days.last, settings)}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'هفتهٔ بعد',
                      onPressed: () => _shiftWeek(1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final day in days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Semantics(
                            label: formatDate(day, settings, withWeekday: true),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(48, 64),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                backgroundColor:
                                    daysBetween(day, _selected) == 0
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                              ),
                              onPressed: () => setState(() => _selected = day),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  children: [
                                    Text(weekdayInitials[day.weekday - 1]),
                                    Text(persianDigits(
                                      settings.isJalali
                                          ? formatDate(day, settings).split(' ').first
                                          : '${day.day}',
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  formatDate(_selected, settings, withWeekday: true),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  Column(
                    children: [
                      const Text('دریافت کارهای تقویم ممکن نشد.'),
                      TextButton(
                        onPressed: _load,
                        child: const Text('تلاش دوباره'),
                      ),
                    ],
                  )
                else if (selectedTasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('برای این روز کاری زمان‌بندی نشده است.'),
                  )
                else
                  for (final task in selectedTasks)
                    ListTile(
                      key: ValueKey('calendar-task-${task.id}'),
                      title: Text(task.title),
                      leading: const Icon(Icons.radio_button_unchecked),
                      subtitle: task.due!.isTimed
                          ? const Text('کار زمان‌دار')
                          : null,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
