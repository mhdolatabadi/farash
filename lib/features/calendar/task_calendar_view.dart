import 'package:menval/core/calendar/calendar_month.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/calendar/jalali.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/calendar/task_month_view.dart';
import 'package:menval/features/calendar/week_time_grid.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:flutter/material.dart';

typedef CalendarTaskLoader =
    Future<List<Task>> Function(DateTime from, DateTime to);

/// Menval's own task calendar. Calendar providers can be separate overlays.
class TaskCalendarView extends StatefulWidget {
  const TaskCalendarView({
    super.key,
    required this.loadTasks,
    this.now,
    this.embedded = false,
  });

  final CalendarTaskLoader loadTasks;
  final DateTime Function()? now;

  /// Hide the page title when hosted inside Menval's shared shell.
  final bool embedded;

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  late DateTime _selected = dayOf((widget.now ?? DateTime.now)());
  bool _showMonth = false;
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
  void didUpdateWidget(covariant TaskCalendarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadTasks != widget.loadTasks) {
      // Parent may have switched accounts. Clear private data before paint
      // and reject results from the previous account's pending request.
      ++_generation;
      _tasks = const [];
      _loading = true;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
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

  void _selectDay(DateTime day) {
    final previousWeek = _start;
    setState(() => _selected = dayOf(day));
    if (daysBetween(previousWeek, _start) != 0) _load();
  }

  void _shiftWeek(int offset) => _selectDay(
    DateTime(_selected.year, _selected.month, _selected.day + offset * 7),
  );

  void _openTask(Task task) {
    final due = task.due;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (due != null)
                Text(
                  due.isTimed
                      ? '${formatDate(due.day, CalendarScope.of(context))} · ${formatTime(due.localTime!)}'
                      : '${formatDate(due.day, CalendarScope.of(context))} · تمام‌روز',
                ),
              if (task.durationMinutes != null)
                Text('مدت: ${formatDuration(task.durationMinutes!)}')
              else if (due?.isTimed == true)
                const Text(
                  'مدت تعیین نشده؛ روی تقویم ۳۰ دقیقه نمایش داده می‌شود.',
                ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(task.description),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('بستن'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = CalendarScope.of(context);
    final theme = Theme.of(context);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(_start.year, _start.month, _start.day + i),
    ];
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('تقویم'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _showMonth = !_showMonth),
                  child: Text(_showMonth ? 'هفته' : 'ماه'),
                ),
              ],
            ),
      body: _showMonth
          ? TaskMonthView(loadTasks: widget.loadTasks, now: widget.now)
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'هفتهٔ بعد',
                          onPressed: () => _shiftWeek(1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        TextButton(
                          onPressed: () =>
                              _selectDay(dayOf((widget.now ?? DateTime.now)())),
                          child: const Text('امروز'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => Row(
                          children: [
                            Expanded(
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _error != null
                                  ? Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'دریافت کارهای تقویم ممکن نشد.',
                                          ),
                                          TextButton(
                                            onPressed: _load,
                                            child: const Text('تلاش دوباره'),
                                          ),
                                        ],
                                      ),
                                    )
                                  : WeekTimeGrid(
                                      start: _start,
                                      tasks: _tasks,
                                      selected: _selected,
                                      now: (widget.now ?? DateTime.now)(),
                                      onSelectDay: _selectDay,
                                      onOpenTask: _openTask,
                                    ),
                            ),
                            if (constraints.maxWidth >= 1320) ...[
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 230,
                                child: _MiniMonth(
                                  selected: _selected,
                                  onSelectDay: _selectDay,
                                  tasks: _tasks,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A compact sidebar month picker on wide screens, like the reference.
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.selected,
    required this.onSelectDay,
    required this.tasks,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelectDay;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final settings = CalendarScope.of(context);
    final month = monthContaining(selected, settings);
    final current = settings.isJalali
        ? JalaliDate.fromGregorian(selected)
        : null;
    final title = settings.isJalali
        ? '${jalaliMonths[current!.month - 1]} ${persianDigits('${current.year}')}'
        : '${gregorianMonths[selected.month - 1]} ${persianDigits('${selected.year}')}';
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdayInitials[(settings.weekStart - 1 + i) % 7],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 1,
            mainAxisSpacing: 3,
          ),
          itemCount: month.days.length,
          itemBuilder: (context, index) {
            final day = month.days[index];
            final inMonth =
                !day.isBefore(month.firstDay) && !day.isAfter(month.lastDay);
            final active = daysBetween(selected, day) == 0;
            final isToday = daysBetween(now, day) == 0;
            final number = settings.isJalali
                ? JalaliDate.fromGregorian(day).day
                : day.day;
            return Tooltip(
              message: formatDate(day, settings, withWeekday: true),
              child: InkWell(
                key: ValueKey('mini-month-${dateKey(day)}'),
                borderRadius: BorderRadius.circular(24),
                onTap: () => onSelectDay(day),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    border: isToday
                        ? Border.all(
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      persianDigits('$number'),
                      style: TextStyle(
                        fontSize: 11,
                        color: inMonth
                            ? null
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(
          'کارهای این هفته: ${persianDigits('${tasks.length}')}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
