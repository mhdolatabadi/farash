import 'package:flutter/material.dart';
import 'package:farash/app/list_app_bar.dart';
import 'package:farash/app/palette.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

/// The views that gather tasks by date from every project.
enum DueView {
  today('امروز', Icons.wb_twilight),
  upcoming('پیش رو', Icons.date_range);

  const DueView(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// How far ahead «پیش رو» looks.
const upcomingDays = 14;

/// Readable width, as in a project.
const _maxListWidth = 760.0;

/// امروز: what is late and what is due today, from all projects, with the
/// late ones movable to today in one action. پیش رو: the coming days as an
/// agenda under a week strip. Tasks open in their own project.
class DueTasksView extends StatefulWidget {
  const DueTasksView({
    super.key,
    required this.view,
    required this.api,
    required this.token,
    required this.projects,
    required this.onOpenProject,
    this.now,
  });

  final DueView view;
  final TasksApi api;
  final String? Function() token;
  final List<Project> Function() projects;
  final ValueChanged<Project> onOpenProject;

  /// The clock, for tests.
  final DateTime Function()? now;

  @override
  State<DueTasksView> createState() => _DueTasksViewState();
}

class _DueTasksViewState extends State<DueTasksView> {
  List<Task> _tasks = const [];
  bool _loading = true;
  Object? _error;
  final _dayKeys = <String, GlobalKey>{};

  DateTime get _today => dayOf((widget.now ?? DateTime.now)());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.token();
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = _today;
      final tasks = widget.view == DueView.today
          ? await widget.api.listDueTasks(token, to: today)
          : await widget.api.listDueTasks(
              token,
              from: today.add(const Duration(days: 1)),
              to: today.add(const Duration(days: upcomingDays)),
            );
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _snack(String message, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: undo == null
            ? null
            : SnackBarAction(label: 'برگرداندن', onPressed: undo),
      ),
    );
  }

  Future<void> _run(Future<void> Function(String token) action) async {
    final token = widget.token();
    if (token == null) return;
    try {
      await action(token);
    } catch (error) {
      if (mounted) showTaskError(context, error);
    }
  }

  Future<void> _complete(Task task) => _run((token) async {
    await widget.api.closeTask(token, task.id);
    if (!mounted) return;
    setState(() => _tasks = [..._tasks]..removeWhere((t) => t.id == task.id));
    _snack(
      '«${task.title}» انجام شد.',
      undo: () => _run((token) async {
        await widget.api.reopenTask(token, task.id);
        await _load();
      }),
    );
  });

  /// Moves every late task to today, keeping each one's other fields;
  /// undo puts each back on its own day.
  Future<void> _moveLateToToday(List<Task> late) => _run((token) async {
    await widget.api.rescheduleTasks(token, [
      for (final t in late) t.id,
    ], TaskDue.onDay(_today));
    await _load();
    if (!mounted) return;
    _snack(
      '${persianDigits(late.length)} کار به امروز آمد.',
      undo: () => _run((token) async {
        for (final t in late) {
          await widget.api.rescheduleTasks(token, [t.id], t.due);
        }
        await _load();
      }),
    );
  });

  Project? _projectOf(Task task) {
    for (final p in widget.projects()) {
      if (p.id == task.projectId) return p;
    }
    return null;
  }

  Widget _row(Task task, {required bool last}) {
    final project = _projectOf(task);
    return TaskTile(
      key: ValueKey(task.id),
      task: task,
      divider: !last,
      tag: project == null ? null : _ProjectTag(project: project),
      onToggle: () => _complete(task),
      onOpen: () {
        if (project != null) widget.onOpenProject(project);
      },
    );
  }

  /// One pane of glass holding a day's tasks.
  Widget _card(List<Task> tasks) {
    final glass = FarashGlassColors.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: glass.pane,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: glass.paneBorder),
          boxShadow: [
            if (light)
              BoxShadow(
                color: glass.shadow,
                offset: const Offset(0, 8),
                blurRadius: 24,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < tasks.length; i++)
                  _row(tasks[i], last: i == tasks.length - 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _todayBody() {
    final settings = CalendarScope.of(context);
    final today = _today;
    final late = [
      for (final t in _tasks)
        if (daysBetween(today, t.due!.day) < 0) t,
    ];
    final now = [
      for (final t in _tasks)
        if (daysBetween(today, t.due!.day) == 0) t,
    ];
    return [
      if (late.isNotEmpty) ...[
        _DayHeading(
          title: 'دیرشده',
          late: true,
          action: TextButton.icon(
            onPressed: () => _moveLateToToday(late),
            icon: const Icon(Icons.event_repeat),
            label: const Text('انتقال همه به امروز'),
          ),
        ),
        _card(late),
      ],
      _DayHeading(
        title: 'امروز',
        detail: formatDate(today, settings, today: today, withWeekday: true),
      ),
      if (now.isEmpty) const _Quiet('برای امروز کاری نمانده.') else _card(now),
    ];
  }

  List<Widget> _upcomingBody() {
    final settings = CalendarScope.of(context);
    final today = _today;
    return [
      for (var offset = 1; offset <= upcomingDays; offset++)
        ...() {
          final day = today.add(Duration(days: offset));
          final tasks = [
            for (final t in _tasks)
              if (daysBetween(day, t.due!.day) == 0) t,
          ];
          final key = _dayKeys.putIfAbsent(dateKey(day), GlobalKey.new);
          return [
            _DayHeading(
              key: key,
              title: relativeDay(day, settings, today: today),
              detail: formatDate(day, settings, today: today),
            ),
            if (tasks.isEmpty) const _Quiet('کاری نیست.') else _card(tasks),
          ];
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = widget.view == DueView.today;
    final count = _tasks.isEmpty
        ? (today ? 'کار بازی نمانده' : 'کاری در دو هفتهٔ پیش رو نیست')
        : '${persianDigits(_tasks.length)} کار';
    final Widget body;
    if (_loading && _tasks.isEmpty) {
      body = const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null && _tasks.isEmpty) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(taskErrorMessage(_error!)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = SliverList.list(children: today ? _todayBody() : _upcomingBody());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset = width > _maxListWidth ? (width - _maxListWidth) / 2 : 0.0;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final topPadding = MediaQuery.paddingOf(context).top;
        return RefreshIndicator(
          onRefresh: _load,
          edgeOffset: topPadding + listBarHeight,
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: ListAppBar(
                  title: widget.view.title,
                  subtitle: count,
                  mark: Icon(
                    widget.view.icon,
                    color: theme.colorScheme.primary,
                  ),
                  actions: [
                    IconButton(
                      tooltip: 'به‌روزرسانی',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                  topPadding: topPadding,
                  inset: inset,
                  expandedHeight: constraints.maxHeight < 240 ? 0 : 76 * scale,
                ),
              ),
              if (!today)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: _WeekStrip(
                      today: _today,
                      busy: {for (final t in _tasks) dateKey(t.due!.day)},
                      onPick: (day) {
                        final target = _dayKeys[dateKey(day)]?.currentContext;
                        if (target != null) {
                          Scrollable.ensureVisible(
                            target,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      },
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(inset, 0, inset, 32),
                sliver: body,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A day's heading in the agenda, with an optional action at its end.
class _DayHeading extends StatelessWidget {
  const _DayHeading({
    super.key,
    required this.title,
    this.detail,
    this.action,
    this.late = false,
  });

  final String title;
  final String? detail;
  final Widget? action;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: late ? theme.colorScheme.error : null,
                      ),
                    ),
                    if (detail != null)
                      TextSpan(
                        text: '  $detail',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 24, 4),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The project a gathered task belongs to.
class _ProjectTag extends StatelessWidget {
  const _ProjectTag({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        project.isInbox
            ? Icon(Icons.inbox_outlined, size: 14, color: color)
            : Icon(Icons.circle, size: 8, color: project.swatch),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            project.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// The coming week as a row of days; a dot marks days with tasks, and a
/// tap scrolls the agenda to that day.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.today,
    required this.busy,
    required this.onPick,
  });

  final DateTime today;
  final Set<String> busy;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = CalendarScope.of(context);
    final days = [for (var i = 1; i <= 7; i++) today.add(Duration(days: i))];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          for (final day in days)
            Expanded(
              child: Tooltip(
                message: formatDate(
                  day,
                  settings,
                  today: today,
                  withWeekday: true,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onPick(day),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          weekdayInitials[day.weekday - 1],
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // The day of the month in the chosen calendar.
                          formatDate(
                            day,
                            settings,
                            today: today,
                          ).split(' ').first,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: busy.contains(dateKey(day))
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
