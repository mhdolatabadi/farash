import 'dart:math' as math;

import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/calendar/week_event_layout.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:flutter/material.dart';

/// Scrollable, accessible seven-day timetable with real-time positions.
/// This is a view of Farash tasks, not a Google Calendar data import.
class WeekTimeGrid extends StatefulWidget {
  const WeekTimeGrid({
    super.key,
    required this.start,
    required this.tasks,
    required this.selected,
    required this.now,
    required this.onSelectDay,
    required this.onOpenTask,
  });

  final DateTime start;
  final List<Task> tasks;
  final DateTime selected;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDay;
  final ValueChanged<Task> onOpenTask;

  @override
  State<WeekTimeGrid> createState() => _WeekTimeGridState();
}

class _WeekTimeGridState extends State<WeekTimeGrid> {
  static const _gutter = 64.0;
  static const _hourHeight = 68.0;
  static const _minDayWidth = 136.0;
  late final ScrollController _vertical = ScrollController(
    initialScrollOffset: 8 * _hourHeight,
  );
  final ScrollController _horizontal = ScrollController();
  bool _scrollToSelectedDay = true;

  @override
  void didUpdateWidget(covariant WeekTimeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.selected != widget.selected) {
      _scrollToSelectedDay = true;
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      final settings = CalendarScope.of(context);
      final width = math.max(constraints.maxWidth, _gutter + _minDayWidth * 7);
      final dayWidth = (width - _gutter) / 7;
      if (_scrollToSelectedDay) {
        _scrollToSelectedDay = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_horizontal.hasClients) return;
          final day = daysBetween(widget.start, widget.selected).clamp(0, 6);
          final target = math.max(0, day - 1) * dayWidth;
          _horizontal.jumpTo(
            target.clamp(0.0, _horizontal.position.maxScrollExtent).toDouble(),
          );
        });
      }
      final days = [
        for (var i = 0; i < 7; i++)
          DateTime(widget.start.year, widget.start.month, widget.start.day + i),
      ];
      final allDay = [
        for (var day = 0; day < 7; day++)
          widget.tasks.where((task) {
            return task.due?.isTimed == false &&
                weekDayIndex(task, widget.start) == day;
          }).toList(),
      ];
      final blocks = layoutWeekEvents(widget.tasks, widget.start);
      final maxAllDay = allDay.fold<int>(
        0,
        (previous, value) => math.max(previous, value.length),
      );
      final allDayHeight = maxAllDay == 0
          ? 36.0
          : maxAllDay == 1
          ? 42.0
          : maxAllDay > 2 ? 104.0 : 74.0;
      final todayIndex = daysBetween(widget.start, widget.now);
      final timeY =
          (widget.now.hour * 60 + widget.now.minute) / 60 * _hourHeight;

      return SingleChildScrollView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  children: [
                    const SizedBox(width: _gutter),
                    for (final day in days)
                      SizedBox(
                        width: dayWidth,
                        child: Center(
                          child: Semantics(
                            label: formatDate(day, settings, withWeekday: true),
                            selected: daysBetween(widget.selected, day) == 0,
                            button: true,
                            child: InkWell(
                              key: ValueKey('week-day-${dateKey(day)}'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => widget.onSelectDay(day),
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 48,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: daysBetween(widget.selected, day) == 0
                                      ? scheme.primaryContainer
                                      : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      weekdayNames[day.weekday - 1],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                    Text(
                                      persianDigits(
                                        settings.isJalali
                                            ? formatDate(
                                                day,
                                                settings,
                                              ).split(' ').first
                                            : '${day.day}',
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: allDayHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _gutter,
                      child: Center(
                        child: Text(
                          'تمام‌روز',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ),
                    for (var day = 0; day < 7; day++)
                      SizedBox(
                        width: dayWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: scheme.outlineVariant,
                                width: 0.5,
                              ),
                              bottom: BorderSide(
                                color: scheme.outlineVariant,
                                width: 0.5,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final task in allDay[day].take(2))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Material(
                                    color: scheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(5),
                                    child: InkWell(
                                      key: ValueKey('week-all-day-${task.id}'),
                                      onTap: () => widget.onOpenTask(task),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          task.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSecondaryContainer,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (allDay[day].length > 2)
                                SizedBox(
                                  height: 48,
                                  child: TextButton(
                                    key: ValueKey('week-all-day-more-${dateKey(days[day])}'),
                                    onPressed: () {
                                      widget.onSelectDay(days[day]);
                                      showModalBottomSheet<void>(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (sheetContext) => SafeArea(
                                          child: ListView(
                                            shrinkWrap: true,
                                            children: [
                                              for (final task in allDay[day])
                                                ListTile(
                                                  title: Text(task.title),
                                                  onTap: () {
                                                    Navigator.pop(sheetContext);
                                                    widget.onOpenTask(task);
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      '+${persianDigits('${allDay[day].length - 2}')} کار دیگر',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _vertical,
                  child: SizedBox(
                    height: 24 * _hourHeight,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (var hour = 0; hour <= 24; hour++)
                          Positioned(
                            top: hour * _hourHeight,
                            right: _gutter,
                            left: 0,
                            child: Container(
                              height: 1,
                              color: scheme.outlineVariant,
                            ),
                          ),
                        for (var day = 0; day <= 7; day++)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: _gutter + day * dayWidth,
                            child: Container(
                              width: 0.5,
                              color: scheme.outlineVariant,
                            ),
                          ),
                        for (var hour = 0; hour < 24; hour++)
                          Positioned(
                            top: hour * _hourHeight + 4,
                            right: 2,
                            width: _gutter - 8,
                            child: Text(
                              persianDigits(
                                '${hour.toString().padLeft(2, '0')}:00',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        for (final placement in blocks)
                          _event(placement, dayWidth, scheme),
                        if (todayIndex >= 0 && todayIndex < 7)
                          Positioned(
                            top: timeY,
                            right: _gutter + todayIndex * dayWidth,
                            width: dayWidth,
                            child: IgnorePointer(
                              child: Container(height: 2, color: scheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _event(WeekEventPlacement block, double dayWidth, ColorScheme scheme) {
    const gap = 3.0;
    final laneWidth = (dayWidth - gap * 2) / block.columns;
    final top = block.startMinute / 60 * _hourHeight;
    final height = math.min(
      24 * _hourHeight - top,
      math.max(
        24.0,
        (block.endMinute - block.startMinute) / 60 * _hourHeight - 2,
      ),
    );
    // Each overnight segment belongs to its own calendar day. The original
    // task due time is still available in the task details sheet.
    String clock(int minute) => persianDigits(
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
    );
    final startTime = clock(block.startMinute);
    final displayTime = block.task.durationMinutes == null
        ? startTime
        : '$startTime–${clock(block.endMinute)}';
    final color = block.task.isCompleted
        ? scheme.surfaceContainerHighest
        : block.task.priority == TaskPriority.p1
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final textColor = block.task.priority == TaskPriority.p1
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
    return Positioned(
      top: top,
      right:
          _gutter + block.dayIndex * dayWidth + block.column * laneWidth + gap,
      width: laneWidth - gap,
      height: height,
      child: Semantics(
        label: '${block.task.title}، $displayTime',
        button: true,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('week-timed-${block.task.id}-${block.dayIndex}'),
            onTap: () => widget.onOpenTask(block.task),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.task.title,
                    maxLines: height > 70 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                  if (height > 42)
                    Text(
                      displayTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
