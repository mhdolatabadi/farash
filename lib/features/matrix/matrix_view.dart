import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/labels/application/labels_controller.dart';
import 'package:menval/features/matrix/matrix.dart';
import 'package:menval/features/projects/data/project.dart';
import 'package:menval/features/search/search.dart';
import 'package:menval/features/tasks/application/tasks_controller.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/task_detail_sheet.dart';
import 'package:menval/features/tasks/presentation/task_tile.dart';

/// Wide enough for the quadrants to sit two by two.
const matrixGridBreakpoint = 720.0;

/// The change that moves [task] into [target]: important quadrants raise a
/// p3–p4 task to p1 and the others lower a p1–p2 task to p4; urgent ones
/// bring a later or undated task to today and the others move a late or
/// today task to tomorrow. Null when nothing needs to change.
TaskDraft? moveIntoQuadrant(Task task, Quadrant target, {DateTime? now}) {
  final today = dayOf(now ?? DateTime.now());
  final important = task.priority.level <= 2;
  final due = task.due;
  final urgent = due != null && !due.day.isAfter(today);
  final priority = target.important == important
      ? null
      : (target.important ? TaskPriority.p1 : TaskPriority.p4);
  TaskDates? dates;
  if (target.urgent != urgent) {
    final day = target.urgent ? today : today.add(const Duration(days: 1));
    final TaskDue moved;
    if (due != null && due.isTimed) {
      final time = due.localTime!;
      moved = TaskDue.at(
        DateTime(day.year, day.month, day.day, time.hour, time.minute),
        due.timezone ?? 'UTC',
      );
    } else {
      moved = TaskDue.onDay(day);
    }
    dates = TaskDates(
      due: moved,
      deadline: task.deadline,
      durationMinutes: task.durationMinutes,
    );
  }
  if (priority == null && dates == null) return null;
  return TaskDraft(priority: priority, dates: dates);
}

/// TickTick's Eisenhower matrix over the account's open tasks.
class MatrixView extends StatefulWidget {
  const MatrixView({
    super.key,
    required this.search,
    required this.tasks,
    required this.token,
    required this.projects,
    required this.rules,
    this.sections,
    this.labels,
  });

  final SearchApi search;
  final TasksApi tasks;
  final SectionsApi? sections;
  final LabelsController? labels;
  final String? Function() token;
  final List<Project> Function() projects;
  final MatrixRules rules;

  @override
  State<MatrixView> createState() => _MatrixViewState();
}

class _MatrixViewState extends State<MatrixView> {
  final _tasks = <Quadrant, List<Task>>{};
  final _errors = <Quadrant>{};
  bool _loading = true, _busy = false;
  String? _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.rules.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    widget.rules.removeListener(_load);
    super.dispose();
  }

  String get _token {
    final value = widget.token();
    if (value == null) throw StateError('signed out');
    return value;
  }

  Future<void> _load() async {
    final serial = ++_generation;
    setState(() => _loading = true);
    final today = dateKey(DateTime.now());
    final results = await Future.wait([
      for (final q in Quadrant.values)
        () async {
          try {
            final path = Uri(
              path: '/api/v1/search',
              queryParameters: {
                'q': widget.rules.rule(q),
                'today': today,
                'sort': 'due',
                'limit': '100',
              },
            ).toString();
            return SearchPage.fromJson(
              await widget.search.searchRequest(_token, 'GET', path),
            ).tasks;
          } catch (_) {
            return null;
          }
        }(),
    ]);
    if (!mounted || serial != _generation) return;
    setState(() {
      _loading = false;
      _errors.clear();
      for (final (i, q) in Quadrant.values.indexed) {
        final found = results[i];
        if (found == null) _errors.add(q);
        _tasks[q] = found ?? const [];
      }
    });
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _message = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(Task task, Quadrant target) async {
    final change = moveIntoQuadrant(task, target);
    if (change == null) return;
    await _run(
      () => widget.tasks.updateTask(_token, task.id, change),
      'کار جابه‌جا نشد؛ دوباره تلاش کنید.',
    );
  }

  Future<void> _toggle(Task task) => _run(
    () => task.isCompleted
        ? widget.tasks.reopenTask(_token, task.id)
        : widget.tasks.closeTask(_token, task.id),
    'تغییر کار تأیید نشد. دوباره تلاش کنید.',
  );

  Future<void> _open(Task task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final controller = TasksController(
      api: widget.tasks,
      sectionsApi: widget.sections,
      token: widget.token,
      projectId: task.projectId,
    );
    try {
      await controller.setShowCompleted(true);
      final current = controller.taskById(task.id);
      if (!mounted) return;
      if (controller.error != null || current == null) {
        setState(() => _message = 'جزئیات کار دریافت نشد؛ دوباره تلاش کنید.');
        return;
      }
      await showTaskDetailSheet(
        context,
        controller: controller,
        task: current,
        projects: widget.projects(),
        labels: widget.labels,
      );
    } finally {
      controller.dispose();
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _editRule(Quadrant q) async {
    final rule = await showDialog<String>(
      context: context,
      builder: (context) =>
          _RuleDialog(quadrant: q, rule: widget.rules.rule(q)),
    );
    if (rule != null) await widget.rules.setRule(q, rule);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= matrixGridBreakpoint;
    final panels = [
      for (final q in Quadrant.values)
        _QuadrantPanel(
          key: ValueKey('quadrant-${q.name}'),
          quadrant: q,
          tasks: _tasks[q] ?? const [],
          failed: _errors.contains(q),
          busy: _busy,
          touch: !wide,
          projects: widget.projects(),
          onToggle: _toggle,
          onOpen: _open,
          onDrop: (task) => _move(task, q),
          onEditRule: () => _editRule(q),
          onRetry: _load,
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ماتریس آیزنهاور'),
        actions: [
          IconButton(
            tooltip: 'به‌روزرسانی',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_message case final message?)
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: wide
                  ? Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: Column(
                        children: [
                          for (final row in [
                            panels.sublist(0, 2),
                            panels.sublist(2),
                          ])
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final panel in row)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(Space.xs),
                                        child: panel,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter - 2,
                        Space.sm,
                        Space.gutter - 2,
                        Space.xl,
                      ),
                      children: [
                        for (final panel in panels)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.md),
                            child: panel,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuadrantPanel extends StatelessWidget {
  const _QuadrantPanel({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.failed,
    required this.busy,
    required this.touch,
    required this.projects,
    required this.onToggle,
    required this.onOpen,
    required this.onDrop,
    required this.onEditRule,
    required this.onRetry,
  });

  final Quadrant quadrant;
  final List<Task> tasks;
  final bool failed, busy, touch;
  final List<Project> projects;
  final ValueChanged<Task> onToggle, onOpen, onDrop;
  final VoidCallback onEditRule, onRetry;

  Color _accent(ColorScheme scheme) => switch (quadrant) {
    Quadrant.doFirst => scheme.error,
    Quadrant.schedule => scheme.primary,
    Quadrant.delegate => scheme.tertiary,
    Quadrant.later => scheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(theme.colorScheme);
    Widget tile(Task task) {
      final row = TaskTile(
        task: task,
        dense: true,
        divider: task != tasks.last,
        onToggle: () => onToggle(task),
        onOpen: () => onOpen(task),
        tag: Text(
          projects.where((p) => p.id == task.projectId).firstOrNull?.name ??
              'پروژه',
        ),
      );
      final feedback = Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.all(Space.sm),
            child: Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      final dim = Opacity(opacity: .4, child: row);
      return IgnorePointer(
        ignoring: busy,
        child: touch
            ? LongPressDraggable<Task>(
                data: task,
                feedback: feedback,
                childWhenDragging: dim,
                child: row,
              )
            : Draggable<Task>(
                data: task,
                feedback: feedback,
                childWhenDragging: dim,
                child: row,
              ),
      );
    }

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => !tasks.any((t) => t.id == d.data.id),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => Semantics(
        container: true,
        label: quadrant.title,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: candidates.isNotEmpty ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: SoftWell(
            child: Column(
              mainAxisSize: touch ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.md,
                    Space.xs,
                    Space.xs,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: accent),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          quadrant.title,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        persianDigits(tasks.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        tooltip: 'قاعدهٔ «${quadrant.title}»',
                        onPressed: onEditRule,
                        icon: const Icon(Icons.tune, size: 20),
                      ),
                    ],
                  ),
                ),
                if (failed)
                  ListTile(
                    title: const Text('کارها دریافت نشدند.'),
                    trailing: TextButton(
                      onPressed: onRetry,
                      child: const Text('تلاش دوباره'),
                    ),
                  )
                else if (tasks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Text(
                      'کاری اینجا نیست.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (touch)
                  Column(children: [for (final t in tasks) tile(t)])
                else
                  Expanded(
                    child: ListView(children: [for (final t in tasks) tile(t)]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edits a quadrant's rule in the search query language.
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({required this.quadrant, required this.rule});

  final Quadrant quadrant;
  final String rule;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _rule = TextEditingController(text: widget.rule);

  @override
  void dispose() {
    _rule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('قاعدهٔ «${widget.quadrant.title}»'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _rule,
            autofocus: true,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'عبارت فیلتر'),
          ),
          Text(
            'مثل جست‌وجو: p1 تا p4، امروز، دیرشده، "7 days"، "no date"، #پروژه و @برچسب، با &، |، ! و پرانتز.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, widget.quadrant.defaultRule),
        child: const Text('پیش‌فرض'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _rule.text),
        child: const Text('ذخیره'),
      ),
    ],
  );
}
