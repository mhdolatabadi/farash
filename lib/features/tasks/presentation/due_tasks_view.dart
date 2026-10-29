import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/app/list_app_bar.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/application/quick_capture.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';
import 'package:farash/features/tasks/presentation/today_bento.dart';

/// The views that gather tasks by date from every project.
enum DueView {
  today('امروز', Icons.today_outlined),
  upcoming('پیش رو', Icons.date_range),
  week('۷ روز آینده', Icons.view_week_outlined),
  all('همه', Icons.all_inbox_outlined);

  const DueView(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// How far ahead «پیش رو» looks.
const upcomingDays = 14;

/// How far ahead «همه» looks; the API caps a range at a year.
const allDays = 365;

/// Readable width, as in a project.
const _maxListWidth = 760.0;

/// امروز: what is late and what is due today, from all projects, with the
/// late ones movable to today in one action, and a capture bar that adds
/// to the Inbox for today. پیش رو: the coming days as an agenda under a
/// week strip. A task opens in the editor where it is.
class DueTasksView extends StatefulWidget {
  const DueTasksView({
    super.key,
    required this.view,
    required this.api,
    required this.token,
    required this.projects,
    required this.onOpenProject,
    this.label,
    this.labels,
    this.sectionsApi,
    this.now,
    this.doneToday,
    this.focus,
    this.onOpenFocus,
    this.habits,
    this.onOpenHabits,
  });

  final DueView view;
  final TasksApi api;
  final String? Function() token;
  final List<Project> Function() projects;
  final ValueChanged<Project> onOpenProject;

  /// Shows this label's open tasks from every project instead of [view].
  final Label? label;

  /// The account's labels, for the rows' tags and the label's own tasks.
  final LabelsController? labels;

  /// For the editor's section choice; null where sections are unavailable.
  final SectionsApi? sectionsApi;

  /// The clock, for tests.
  final DateTime Function()? now;

  /// How many tasks the server counts as completed today, for the bento's
  /// progress; null hides the progress.
  final Future<int?> Function()? doneToday;

  /// The focus timer and today's habits, shown as tiles above «امروز».
  final FocusController? focus;
  final VoidCallback? onOpenFocus;
  final HabitsController? habits;
  final VoidCallback? onOpenHabits;

  @override
  State<DueTasksView> createState() => _DueTasksViewState();
}

class _DueTasksViewState extends State<DueTasksView> {
  List<Task> _tasks = const [];
  bool _loading = true;
  bool _openingTask = false;
  int? _doneToday;
  Object? _error;
  String? _captureError;
  final _dayKeys = <String, GlobalKey>{};
  late final _captureSession = QuickCaptureSession(
    api: widget.api,
    sections: widget.sectionsApi,
    labels: widget.labels,
    token: () => widget.token(),
    projects: () => widget.projects(),
    defaultProject: () {
      final inbox = widget.projects().where((p) => p.isInbox).firstOrNull;
      if (inbox == null) {
        throw const ApiException(
          'صندوق ورودی در دسترس نیست؛ دوباره تلاش کنید.',
        );
      }
      return inbox;
    },
  );

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
      DateTime plus(int days) =>
          DateTime(today.year, today.month, today.day + days);
      final label = widget.label;
      final labels = widget.labels;
      final tasks = label != null && labels != null
          ? await labels.api.listLabelTasks(token, label.id)
          : switch (widget.view) {
              DueView.today => await widget.api.listDueTasks(token, to: today),
              DueView.upcoming => await widget.api.listDueTasks(
                token,
                from: plus(1),
                to: plus(upcomingDays),
              ),
              DueView.week => await widget.api.listDueTasks(
                token,
                from: today,
                to: plus(6),
              ),
              DueView.all => await widget.api.listDueTasks(
                token,
                to: plus(allDays),
              ),
            };
      if (label != null) labels?.load();
      if (_bento) _loadDone();
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

  /// Today without a label: the bento view.
  bool get _bento => widget.view == DueView.today && widget.label == null;

  /// The progress is a nicety: a failed count only hides it.
  Future<void> _loadDone() async {
    final load = widget.doneToday;
    if (load == null) return;
    try {
      final done = await load();
      if (mounted) setState(() => _doneToday = done);
    } catch (_) {
      if (mounted) setState(() => _doneToday = null);
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
    if (_bento) _loadDone();
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

  /// Moves [task] to [day], keeping its time of day when it has one;
  /// undo puts it back.
  Future<void> _moveTo(Task task, DateTime day) => _run((token) async {
    final due = task.due;
    if (due == null || daysBetween(due.day, day) == 0) return;
    final time = due.localTime;
    final next = due.isTimed && due.timezone != null
        ? TaskDue.at(
            DateTime(day.year, day.month, day.day, time!.hour, time.minute),
            due.timezone!,
          )
        : TaskDue.onDay(day);
    await widget.api.rescheduleTasks(token, [task.id], next);
    await _load();
    if (!mounted) return;
    final settings = CalendarScope.of(context);
    _snack(
      '«${task.title}» به ${relativeDay(day, settings, today: _today)} رفت.',
      undo: () => _run((token) async {
        await widget.api.rescheduleTasks(token, [task.id], due);
        await _load();
      }),
    );
  });

  /// The non-drag way to move a task: pick its day.
  Future<void> _pickDay(Task task) async {
    final picked = await showDuePicker(
      context,
      dueOnly: true,
      initial: task.dates,
      now: _today,
    );
    final day = picked?.due?.day;
    if (day != null && mounted) await _moveTo(task, day);
  }

  /// Opens [task] in the editor over this view, with its project's tasks
  /// loaded behind it for sections and subtasks.
  Future<void> _openTask(Task task) async {
    if (_openingTask) return;
    final requestToken = widget.token();
    if (requestToken == null) return;
    _openingTask = true;
    final controller = TasksController(
      api: widget.api,
      sectionsApi: widget.sectionsApi,
      token: widget.token,
      projectId: task.projectId,
    );
    try {
      // An editor needs the complete project context, including completed
      // children. A failed load must never open a partial, stale editor.
      await controller.setShowCompleted(true);
      if (!mounted || widget.token() != requestToken) return;
      final current = controller.taskById(task.id);
      if (controller.error != null || current == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('جزئیات کار دریافت نشد؛ دوباره تلاش کنید.'),
            action: SnackBarAction(
              label: 'تلاش دوباره',
              onPressed: () => _openTask(task),
            ),
          ),
        );
        return;
      }
      final result = await showTaskDetailSheet(
        context,
        controller: controller,
        task: current,
        projects: widget.projects(),
        labels: widget.labels,
      );
      if (result == TaskSheetResult.deleted) {
        await _run((_) => controller.delete(current));
      }
    } finally {
      controller.dispose();
      _openingTask = false;
    }
    if (mounted && widget.token() == requestToken) await _load();
  }

  /// Adds a task from the capture bar: to the Inbox, or a `#project` typed
  /// in it, due today unless the text names another day.
  Future<bool> _quickAdd(
    QuickTask parsed,
    String raw,
    TaskPriority menuPriority,
  ) async {
    final token = widget.token();
    if (token == null) return false;
    setState(() => _captureError = null);
    try {
      await _captureSession.capture(
        parsed,
        raw,
        calendar: CalendarScope.of(context).isJalali ? 'jalali' : 'gregorian',
        menuPriority: menuPriority,
        defaultDay: _today,
        now: _today,
      );
      await _load();
      return true;
    } catch (error) {
      if (mounted && widget.token() == token) {
        setState(() => _captureError = taskErrorMessage(error));
      }
      return false;
    }
  }

  Project? _projectOf(Task task) {
    for (final p in widget.projects()) {
      if (p.id == task.projectId) return p;
    }
    return null;
  }

  Widget _row(Task task, {required bool last}) {
    final project = _projectOf(task);
    final tile = TaskTile(
      key: ValueKey(task.id),
      task: task,
      divider: !last,
      dense: _bento,
      showToday: widget.view != DueView.today || widget.label != null,
      tag: project == null ? null : _ProjectTag(project: project),
      labels: [for (final id in task.labelIds) ?widget.labels?.byId(id)],
      onToggle: () => _complete(task),
      onOpen: () => _openTask(task),
      trailing: task.due == null
          ? null
          : IconButton(
              tooltip: 'تغییر روز «${task.title}»',
              onPressed: () => _pickDay(task),
              icon: const Icon(Icons.event_outlined),
            ),
    );
    // In the agenda a long press lifts the task to drop on another day.
    if (widget.view == DueView.today || widget.label != null) return tile;
    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(task.title),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  /// A day that accepts a dropped task, lit while one hovers over it.
  Widget _dropOn(DateTime day, Widget child) => DragTarget<Task>(
    onWillAcceptWithDetails: (d) =>
        d.data.due != null && daysBetween(d.data.due!.day, day) != 0,
    onAcceptWithDetails: (d) => _moveTo(d.data, day),
    builder: (context, hovering, _) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: hovering.isEmpty
            ? Colors.transparent
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: child,
    ),
  );

  /// One panel holding a day's tasks.
  Widget _card(List<Task> tasks) {
    // Rows run edge to edge and carry the gutter themselves.
    final list = Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          for (var i = 0; i < tasks.length; i++)
            _row(tasks[i], last: i == tasks.length - 1),
        ],
      ),
    );
    if (!_bento) return list;
    // On the soft ground a day's tasks sit in one well.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter - 2),
      child: SoftWell(child: list),
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
          first: true,
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
        first: late.isEmpty,
        // The bento's date tile already says which day it is.
        detail: _bento
            ? null
            : formatDate(today, settings, today: today, withWeekday: true),
      ),
      if (now.isEmpty) const _Quiet('برای امروز کاری نمانده.') else _card(now),
    ];
  }

  /// The days the agenda shows: tomorrow on for «پیش رو», today on for
  /// «۷ روز آینده».
  List<DateTime> get _agendaDays => switch (widget.view) {
    DueView.week => [
      for (var i = 0; i < 7; i++)
        DateTime(_today.year, _today.month, _today.day + i),
    ],
    _ => [
      for (var i = 1; i <= upcomingDays; i++)
        DateTime(_today.year, _today.month, _today.day + i),
    ],
  };

  List<Widget> _agendaBody() {
    final settings = CalendarScope.of(context);
    final today = _today;
    return [
      for (final day in _agendaDays)
        ...() {
          final tasks = [
            for (final t in _tasks)
              if (daysBetween(day, t.due!.day) == 0) t,
          ];
          final key = _dayKeys.putIfAbsent(dateKey(day), GlobalKey.new);
          return [
            _dropOn(
              day,
              _DayHeading(
                key: key,
                first: day == _agendaDays.first,
                title: relativeDay(day, settings, today: today),
                detail: formatDate(day, settings, today: today),
              ),
            ),
            if (tasks.isEmpty) const _Quiet('کاری نیست.') else _card(tasks),
          ];
        }(),
    ];
  }

  /// Every dated open task, late ones first, grouped by day.
  List<Widget> _allBody() {
    final settings = CalendarScope.of(context);
    final today = _today;
    final groups = <String, List<Task>>{};
    for (final t in _tasks) {
      final late = daysBetween(today, t.due!.day) < 0;
      groups.putIfAbsent(late ? '' : dateKey(t.due!.day), () => []).add(t);
    }
    return [
      for (final MapEntry(:key, :value) in groups.entries) ...[
        key.isEmpty
            ? const _DayHeading(title: 'دیرشده', late: true, first: true)
            : _dropOn(
                parseDateKey(key),
                _DayHeading(
                  first: key == groups.keys.first,
                  title: relativeDay(parseDateKey(key), settings, today: today),
                  detail: formatDate(parseDateKey(key), settings, today: today),
                ),
              ),
        _card(value),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.label;
    final count = _tasks.isEmpty && label != null
        ? 'کار بازی با این برچسب نیست'
        : _tasks.isEmpty
        ? switch (widget.view) {
            DueView.today => 'کار بازی نمانده',
            DueView.upcoming => 'کاری در دو هفتهٔ پیش رو نیست',
            DueView.week => 'کاری در این هفت روز نیست',
            DueView.all => 'کار زمان‌داری نمانده',
          }
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
      body = SliverList.list(
        children: label != null
            ? [
                const SizedBox(height: Space.sm),
                if (_tasks.isEmpty)
                  const _Quiet('هنوز کاری این برچسب را ندارد.')
                else
                  _card(_tasks),
              ]
            : switch (widget.view) {
                DueView.today => _todayBody(),
                DueView.all => _allBody(),
                _ => _agendaBody(),
              },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final inset = width > _maxListWidth ? (width - _maxListWidth) / 2 : 0.0;
        final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
        final topPadding = MediaQuery.paddingOf(context).top;
        final list = RefreshIndicator(
          onRefresh: _load,
          edgeOffset: topPadding + listBarHeight,
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: ListAppBar(
                  background: _bento ? Soft.ground(context) : null,
                  title: label?.tag ?? widget.view.title,
                  subtitle: count,
                  mark: label != null
                      ? Icon(Icons.sell, color: label.swatch)
                      : Icon(
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
                  // The bento's tiles carry the count on «امروز».
                  expandedHeight: _bento || constraints.maxHeight < 240
                      ? 0
                      : 24 * scale,
                ),
              ),
              if (_bento && !(_loading && _tasks.isEmpty))
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: TodayBento(
                      today: _today,
                      open: _tasks.length,
                      done: _doneToday,
                      focus: widget.focus,
                      onOpenFocus: widget.onOpenFocus,
                      habits: widget.habits,
                      onOpenHabits: widget.onOpenHabits,
                    ),
                  ),
                ),
              if (label == null &&
                  (widget.view == DueView.upcoming ||
                      widget.view == DueView.week))
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverToBoxAdapter(
                    child: _WeekStrip(
                      days: _agendaDays.take(7).toList(),
                      today: _today,
                      dropOn: _dropOn,
                      busy: {for (final t in _tasks) dateKey(t.due!.day)},
                      onPick: (day) {
                        final target = _dayKeys[dateKey(day)]?.currentContext;
                        if (target != null) {
                          Scrollable.ensureVisible(
                            target,
                            duration: Motion.of(context, Motion.standard),
                            curve: Motion.enter,
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
        // Today is where the day is planned, so it takes new tasks too.
        if (label != null || widget.view != DueView.today) return list;
        return ColoredBox(
          color: Soft.ground(context),
          child: Column(
            children: [
              Expanded(child: list),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  inset + Space.gutter,
                  Space.sm,
                  inset + Space.gutter,
                  Space.md,
                ),
                child: QuickAddBar(
                  hint: 'افزودن کار برای امروز…',
                  error: _captureError,
                  pending: () => _captureSession.hasPendingRecurrence,
                  onAdd: _quickAdd,
                ),
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
    this.first = false,
  });

  final String title;
  final String? detail;
  final Widget? action;
  final bool late;

  /// Right under the app bar, whose count already leaves room above.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        Space.gutter,
        first ? Space.sm : Space.sectionTop,
        Space.xs,
        Space.sectionBottom,
      ),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: late
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
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
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.sm,
      ),
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
    required this.days,
    required this.dropOn,
    required this.today,
    required this.busy,
    required this.onPick,
  });

  final List<DateTime> days;

  /// Makes a day accept a dropped task.
  final Widget Function(DateTime day, Widget child) dropOn;
  final DateTime today;
  final Set<String> busy;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = CalendarScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          for (final day in days)
            Expanded(
              child: dropOn(
                day,
                Tooltip(
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
            ),
        ],
      ),
    );
  }
}
