import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:flutter/material.dart';
import 'package:farash/app/atelier.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'time_tracking.dart';

Future<bool> startTracking(
  BuildContext context,
  TimeTracker tracker,
  Task task,
) async {
  if (tracker.active?.taskId == task.id) return true;
  if (tracker.active case final active?) {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغییر کارِ در حال ثبت'),
        content: Text('ثبت «${active.title}» متوقف و کار تازه شروع شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('توقف و شروع'),
          ),
        ],
      ),
    );
    if (replace != true || !await tracker.stop(active)) return false;
  }
  return tracker.start(task);
}

class ActiveTimeBar extends StatelessWidget {
  const ActiveTimeBar({super.key, required this.tracker, required this.onOpen});
  final TimeTracker tracker;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tracker,
    builder: (context, _) {
      final entry = tracker.active;
      if (entry == null) return const SizedBox.shrink();
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          trackedTime(entry.elapsed(tracker.now)),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'توقف ثبت زمان',
                  onPressed: tracker.busy ? null : () => tracker.stop(entry),
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class TimeTrackingView extends StatelessWidget {
  const TimeTrackingView({
    super.key,
    required this.tracker,
    required this.tasksApi,
    required this.projects,
  });
  final TimeTracker tracker;
  final TasksApi tasksApi;
  final ProjectsController projects;
  Future<void> _pick(BuildContext context) async {
    try {
      final token = tracker.token();
      if (token == null) return;
      final lists = await Future.wait(
        projects.projects
            .where((p) => !p.isArchived)
            .map((p) => tasksApi.listTasks(token, p.id)),
      );
      if (!context.mounted) return;
      final rootContext = context;
      final tasks = lists
          .expand((e) => e)
          .where((t) => !t.isCompleted)
          .toList();
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (context) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'انتخاب کار برای ثبت زمان',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (tasks.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('ابتدا یک کار اضافه کنید.'),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(tasks[index].title),
                    leading: const Icon(Icons.play_circle_outline),
                    onTap: () {
                      Navigator.pop(context);
                      startTracking(rootContext, tracker, tasks[index]);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فهرست کارها دریافت نشد.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tracker,
    builder: (context, _) {
      final report = tracker.report;
      return CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('زمانِ صرف‌شده'),
            floating: true,
            actions: [
              IconButton(
                tooltip: 'تازه‌سازی زمان‌ها',
                onPressed: tracker.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'وقتت کجا بافته شد؟',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'زمان واقعی کارها؛ جدا از برآورد و امتیاز. هفته از شنبه آغاز می‌شود.',
                      ),
                      const SizedBox(height: 20),
                      if (tracker.error != null)
                        TextButton.icon(
                          onPressed: tracker.load,
                          icon: const Icon(Icons.sync_problem),
                          label: Text(tracker.error!),
                        ),
                      if (report == null && tracker.error == null)
                        const LinearProgressIndicator(),
                      if (report != null) ...[
                        AtelierPanel(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                            spacing: 32,
                            runSpacing: 16,
                            children: [
                              _Total(label: 'امروز', seconds: report.today),
                              _Total(
                                label: 'این هفته',
                                seconds: report.seconds,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: tracker.busy ? null : () => _pick(context),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('شروع برای یک کار'),
                        ),
                        const SizedBox(height: 24),
                        if (tracker.active case final active?) ...[
                          ActiveTimeBar(tracker: tracker, onOpen: () {}),
                          if (active.elapsed(tracker.now) >
                              const Duration(hours: 4))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  const Text(
                                    'این تایمر مدت زیادی روشن مانده؛ اگر فراموشش کرده‌ای زمان را اصلاح کن.',
                                  ),
                                  Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: () => manualTime(
                                          context,
                                          tracker,
                                          Task(
                                            id: active.taskId ?? '',
                                            projectId: '',
                                            title: active.title,
                                          ),
                                          editing: active,
                                        ),
                                        child: const Text('اصلاح بازه'),
                                      ),
                                      TextButton(
                                        onPressed: () => confirmDeleteTime(
                                          context,
                                          tracker,
                                          active,
                                        ),
                                        child: const Text('حذف بازهٔ ناخواسته'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                        ],
                        Text(
                          'به تفکیک کار و پروژه',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        if (report.tasks.isEmpty)
                          const Text(
                            'هنوز زمانی ثبت نشده. از یک کار کوچک شروع کن.',
                          ),
                        for (final item in report.tasks)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item['title'] as String),
                            subtitle: Text(item['project'] as String),
                            trailing: Text(
                              trackedTime(
                                Duration(seconds: item['seconds'] as int),
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          'مرور روزها و بازه‌ها',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Text(
                          'فاصلهٔ بین بازه‌ها ثبت نشده است؛ فقط اگر واقعاً کار کرده‌ای آن را دستی اضافه کن.',
                        ),
                        for (final entry in report.entries) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.title),
                            subtitle: Text(
                              '${formatDate(entry.started.toLocal(), CalendarScope.of(context), alwaysYear: true) + ' ' + persianDigits('${entry.started.toLocal().hour}:${entry.started.toLocal().minute.toString().padLeft(2, '0')}')} · ${trackedTime(entry.elapsed(report.now))}',
                            ),
                            onTap: () => manualTime(
                              context,
                              tracker,
                              Task(
                                id: entry.taskId ?? '',
                                projectId: '',
                                title: entry.title,
                              ),
                              editing: entry,
                            ),
                          ),
                        ],
                        if (report.truncated)
                          const Text(
                            '۵۰۰ بازهٔ اخیر نمایش داده شده؛ جمع زمان شامل همهٔ بازه‌های این هفته است.',
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.seconds});
  final String label;
  final int seconds;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(
        trackedTime(Duration(seconds: seconds)),
        textDirection: TextDirection.ltr,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ],
  );
}

Future<void> confirmDeleteTime(
  BuildContext context,
  TimeTracker tracker,
  TimeEntry entry,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حذف این بازه؟'),
      content: const Text('فقط زمان این بازه حذف می‌شود.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (yes == true) await tracker.remove(entry);
}

Future<void> manualTime(
  BuildContext context,
  TimeTracker tracker,
  Task task, {
  TimeEntry? editing,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _TimeEditor(tracker: tracker, task: task, editing: editing),
);

class _TimeEditor extends StatefulWidget {
  const _TimeEditor({required this.tracker, required this.task, this.editing});
  final TimeTracker tracker;
  final Task task;
  final TimeEntry? editing;
  @override
  State<_TimeEditor> createState() => _TimeEditorState();
}

class _TimeEditorState extends State<_TimeEditor> {
  late DateTime start =
      widget.editing?.started.toLocal() ??
      DateTime.now().subtract(const Duration(minutes: 30));
  late DateTime end = widget.editing?.ended?.toLocal() ?? DateTime.now();
  final key = timeKey();
  String? error;
  bool saving = false;
  Future<void> pick(bool first) async {
    final old = first ? start : end;
    final picked = await showDuePicker(
      context,
      initial: TaskDates(due: TaskDue.onDay(old)),
      dueOnly: true,
    );
    if (picked?.due == null || !mounted) return;
    final date = picked!.due!.day;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(old),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (first) {
        start = value;
      } else {
        end = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.editing == null ? 'ثبت زمانِ تقریبی' : 'اصلاح زمان'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.task.title),
          const SizedBox(height: 12),
          TextButton(
            onPressed: saving ? null : () => pick(true),
            child: Text(
              'از ${formatDate(start, CalendarScope.of(context), alwaysYear: true) + ' ' + persianDigits('${start.hour}:${start.minute.toString().padLeft(2, '0')}')}',
            ),
          ),
          TextButton(
            onPressed: saving ? null : () => pick(false),
            child: Text(
              'تا ${formatDate(end, CalendarScope.of(context), alwaysYear: true) + ' ' + persianDigits('${end.hour}:${end.minute.toString().padLeft(2, '0')}')}',
            ),
          ),
          Text('مدت ${trackedTime(end.difference(start))}'),
          const Text(
            'بازه باید مثبت، حداکثر ۲۴ ساعت و در گذشته باشد. بازه‌های هم‌پوشان در جمع زمان دوبار حساب می‌شوند.',
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (widget.editing case final entry?)
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      await confirmDeleteTime(context, widget.tracker, entry);
                      if (context.mounted) Navigator.pop(context);
                    },
              child: const Text('حذف بازه'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: saving
            ? null
            : () async {
                if (!end.isAfter(start) ||
                    end.isAfter(
                      DateTime.now().add(const Duration(minutes: 1)),
                    ) ||
                    end.difference(start) > const Duration(hours: 24)) {
                  setState(() => error = 'بازهٔ زمانی معتبر نیست.');
                  return;
                }
                setState(() {
                  saving = true;
                  error = null;
                });
                final ok = await widget.tracker.save(
                  widget.task,
                  start,
                  end,
                  key,
                  editing: widget.editing,
                );
                if (!mounted) return;
                if (ok) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    saving = false;
                    error = widget.tracker.error;
                  });
                }
              },
        child: Text(saving ? 'در حال ثبت…' : 'ذخیره'),
      ),
    ],
  );
}

class TaskTimePanel extends StatefulWidget {
  const TaskTimePanel({super.key, required this.tracker, required this.task});
  final TimeTracker tracker;
  final Task task;
  @override
  State<TaskTimePanel> createState() => _TaskTimePanelState();
}

class _TaskTimePanelState extends State<TaskTimePanel> {
  TimeReport? report;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.tracker.addListener(changed);
    load();
  }

  int _revision = -1;
  void changed() {
    if (!widget.tracker.busy && _revision != widget.tracker.revision) {
      _revision = widget.tracker.revision;
      load();
    }
  }

  Future<void> load() async {
    try {
      final r = await widget.tracker.fetch(taskId: widget.task.id);
      if (mounted)
        setState(() {
          report = r;
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'زمان این کار دریافت نشد.');
    }
  }

  @override
  void dispose() {
    widget.tracker.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('زمان این کار', style: Theme.of(context).textTheme.titleMedium),
        if (error != null) TextButton(onPressed: load, child: Text(error!)),
        if (report != null)
          Text(
            '${widget.task.durationMinutes == null ? '' : 'برآورد ${persianDigits(widget.task.durationMinutes!)}د · '}واقعی ${trackedTime(Duration(seconds: report!.seconds))}',
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: widget.tracker.busy
                  ? null
                  : () => startTracking(context, widget.tracker, widget.task),
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('ثبت زمان'),
            ),
            TextButton(
              onPressed: () => manualTime(context, widget.tracker, widget.task),
              child: const Text('افزودن دستی'),
            ),
            if (widget.tracker.focusTask != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.tracker.focusTask!(widget.task);
                },
                child: const Text('تمرکز روی این کار'),
              ),
          ],
        ),
        for (final e in report?.entries.take(3) ?? <TimeEntry>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${formatDate(e.started.toLocal(), CalendarScope.of(context), alwaysYear: true)} · ${trackedTime(e.elapsed(report!.now))}',
            ),
            onTap: () =>
                manualTime(context, widget.tracker, widget.task, editing: e),
          ),
      ],
    ),
  );
}

class TrackerMessage extends StatelessWidget {
  const TrackerMessage({super.key, required this.tracker});
  final TimeTracker tracker;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tracker,
    builder: (context, _) {
      if (tracker.error == null) return const SizedBox.shrink();
      return Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tracker.error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'تازه‌سازی وضعیت ثبت زمان',
                onPressed: tracker.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      );
    },
  );
}
