import 'package:menval/core/calendar/calendar_month.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/calendar/jalali.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/calendar/task_month_view.dart';
import 'package:menval/features/calendar/week_time_grid.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/controls.dart';
import 'package:menval/features/calendar/calendar_event.dart';
import 'package:menval/features/calendar/calendar_event_composer.dart';
import 'package:menval/features/calendar/calendar_events_controller.dart';

typedef CalendarTaskLoader =
    Future<List<Task>> Function(DateTime from, DateTime to);

/// Menval's own task calendar. Calendar providers can be separate overlays.
class TaskCalendarView extends StatefulWidget {
  const TaskCalendarView({
    super.key,
    required this.loadTasks,
    this.now,
    this.embedded = false,
    this.events,
    this.createRequest,
  });

  final CalendarTaskLoader loadTasks;
  final CalendarEventsController? events;
  final ValueListenable<int>? createRequest;
  final DateTime Function()? now;

  /// Hide the page title when hosted inside Menval's shared shell.
  final bool embedded;

  @override
  State<TaskCalendarView> createState() => _TaskCalendarViewState();
}

class _TaskCalendarViewState extends State<TaskCalendarView> {
  late DateTime _selected = dayOf((widget.now ?? DateTime.now)());
  bool _showMonth = false;
  bool _composing = false;
  CalendarEvent? _editing;
  List<CalendarEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    widget.createRequest?.addListener(_createEvent);
  }

  void _createEvent() {
    if (widget.events == null) return;
    setState(() { _showMonth=false; _editing=null; _composing=true; });
  }

  void _openEvent(CalendarEvent event) => setState(() { _editing=event; _composing=true; });

  void _savedEvent() {
    setState(() { _composing=false; _editing=null; });
    _load();
  }

  void _deletedEvent(CalendarEvent event) {
    _savedEvent();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:const Text('رویداد حذف شد.'),action:SnackBarAction(label:'بازگردانی',onPressed:()async{
      if(await widget.events!.setDeleted(event,false)&&mounted) _load();
    })));
  }
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
    if (oldWidget.createRequest != widget.createRequest) {
      oldWidget.createRequest?.removeListener(_createEvent);
      widget.createRequest?.addListener(_createEvent);
    }
    if (oldWidget.events != widget.events) { _events=const []; _composing=false; _editing=null; }
    if (oldWidget.loadTasks != widget.loadTasks || oldWidget.events != widget.events) {
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
    widget.createRequest?.removeListener(_createEvent);
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
      _events = const [];
    });
    try {
      final result = await Future.wait<Object>([
        widget.loadTasks(start,DateTime(start.year,start.month,start.day+6)),
        if(widget.events!=null) widget.events!.load(start,DateTime(start.year,start.month,start.day+7)),
      ]);
      final tasks=result[0] as List<Task>;
      final events=result.length>1 ? result[1] as List<CalendarEvent> : const <CalendarEvent>[];
      if (!mounted || generation != _generation) return;
      setState(() {
        _tasks = tasks;
        _events = events;
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
    // The approved calendar header shows a compact weekday-range label.
    final String weekLabel;
    if (settings.isJalali) {
      final first = JalaliDate.fromGregorian(days.first);
      final last = JalaliDate.fromGregorian(days.last);
      weekLabel = first.year == last.year && first.month == last.month
          ? persianDigits(
              '${first.day} تا ${last.day} ${jalaliMonths[last.month - 1]}',
            )
          : '${formatDate(days.first, settings)} تا ${formatDate(days.last, settings)}';
    } else {
      weekLabel = days.first.month == days.last.month
          ? persianDigits(
              '${days.first.day} تا ${days.last.day} ${gregorianMonths[days.last.month - 1]}',
            )
          : '${formatDate(days.first, settings)} تا ${formatDate(days.last, settings)}';
    }
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('تقویم'),
              actions: [
                if(widget.events==null) TextButton(
                  onPressed: () => setState(() => _showMonth = !_showMonth),
                  child: Text(_showMonth ? 'هفته' : 'ماه'),
                ),
                if(widget.events!=null) MenvalIconButton(tooltip:'رویداد جدید',icon:Icons.add_rounded,onPressed:_createEvent),
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
                            weekLabel,
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
                        if (!widget.embedded)
                          TextButton(
                            onPressed: () => _selectDay(
                              dayOf((widget.now ?? DateTime.now)()),
                            ),
                            child: const Text('امروز'),
                          ),
                      ],
                    ),
                    if(_composing && widget.events!=null) Padding(
                      padding:const EdgeInsets.symmetric(vertical:8),
                      child:CalendarEventComposer(
                        key:ValueKey('event-compose-${_editing?.id ?? 'new'}'),
                        controller:widget.events!,day:_selected,weekStart:_start,existing:_editing,
                        onSaved:_savedEvent,onDeleted:_deletedEvent,
                        onCancel:()=>setState(()=>_composing=false),
                      ),
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
                                  : widget.embedded
                                  ? Padding(
                                      padding: const EdgeInsetsDirectional.only(
                                        top: 4,
                                        bottom: 8,
                                      ),
                                      child: SoftWell(
                                        radius: 34,
                                        padding: const EdgeInsets.all(4),
                                        child: WeekTimeGrid(
                                          start: _start,
                                          tasks: _tasks,
                                          events: _events,
                                          onOpenEvent: _openEvent,
                                          selected: _selected,
                                          now: (widget.now ?? DateTime.now)(),
                                          onSelectDay: _selectDay,
                                          onOpenTask: _openTask,
                                        ),
                                      ),
                                    )
                                  : WeekTimeGrid(
                                      start: _start,
                                      tasks: _tasks,
                                      events: _events,
                                      onOpenEvent: _openEvent,
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
