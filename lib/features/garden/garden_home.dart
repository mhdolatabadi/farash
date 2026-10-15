import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/garden/garden_scene.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/priority_color.dart';

class GardenHome extends StatefulWidget {
  const GardenHome({
    super.key,
    required this.api,
    required this.token,
    required this.projects,
    required this.onTasks,
    required this.onProject,
    required this.onFocus,
  });
  final TasksApi api;
  final String? Function() token;
  final ProjectsController projects;
  final VoidCallback onTasks;
  final ValueChanged<String> onProject;
  final ValueChanged<String?> onFocus;
  @override
  State<GardenHome> createState() => _GardenHomeState();
}

class _GardenHomeState extends State<GardenHome> with WidgetsBindingObserver {
  PersonalProgress? _progress;
  List<Task> _tasks = [];
  bool _loading = true;
  String? _error;
  int _request = 0;
  final _busyTasks = <String>{};
  ApiClient? get _client =>
      widget.api is ApiClient ? widget.api as ApiClient : null;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.projects.addListener(_load);
    _client?.progressChanges.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.projects.removeListener(_load);
    _client?.progressChanges.removeListener(_load);
    _request++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final token = widget.token();
    if (token == null) return;
    final request = ++_request;
    try {
      final now = DateTime.now();
      final due = await widget.api.listDueTasks(
        token,
        to: DateTime(now.year, now.month, now.day),
      );
      final inbox = widget.projects.inbox;
      final tasks = due.isNotEmpty || inbox == null
          ? due
          : await widget.api.listTasks(token, inbox.id);
      PersonalProgress? progress;
      String? error;
      if (_client != null) {
        try {
          progress = await _client!.loadProgress(token, await deviceTimeZone());
        } catch (_) {
          error = 'رشد باغچه دریافت نشد. برای تلاش دوباره لمس کنید.';
        }
      }
      if (!mounted || request != _request || token != widget.token()) return;
      setState(() {
        _progress = progress;
        _tasks = tasks.where((t) => !t.isCompleted).take(3).toList();
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request || token != widget.token()) return;
      setState(() {
        _error = 'اطلاعات باغچه دریافت نشد. برای تلاش دوباره لمس کنید.';
        _loading = false;
      });
    }
  }

  Future<void> _complete(Task task) async {
    final token = widget.token();
    if (token == null || !_busyTasks.add(task.id)) return;
    setState(() {});
    try {
      await widget.api.closeTask(token, task.id);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('یک قدم سبزتر. کار انجام شد.'),
          action: SnackBarAction(
            label: 'برگرداندن',
            onPressed: () async {
              if (!mounted || token != widget.token()) return;
              try {
                await widget.api.reopenTask(token, task.id);
                if (mounted) await _load();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'برگرداندن کار انجام نشد؛ دوباره تلاش کنید.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کار انجام نشد؛ دوباره تلاش کنید.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyTasks.remove(task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final progress = _progress;
    final completed = progress?.completed;
    final stage = completed == null
        ? 'باغچهٔ من'
        : completed == 0
        ? 'شروع یک باغچه'
        : completed < 10
        ? 'اولین جوانه‌ها'
        : completed < 50
        ? 'در مسیر شکفتن'
        : 'یک باغچهٔ پُربار';
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey('garden-scroll'),
        slivers: [
          SliverAppBar(
            title: const Text('باغچهٔ من'),
            floating: true,
            actions: [
              IconButton(
                tooltip: 'تازه‌سازی باغچه',
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: LayoutBuilder(
                    builder: (context, size) {
                      final scene = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'آرام‌آرام، سبزتر.',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (progress != null)
                                Chip(
                                  avatar: const Icon(
                                    Icons.eco_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'سطح ${persianDigits(progress.level)}',
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'هر کارِ انجام‌شده، یک قدم برای رشد.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                          GardenScene(
                            height: size.maxWidth > 650 ? 320 : 250,
                            completed: completed,
                          ),
                          Text(
                            stage,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_loading)
                            const LinearProgressIndicator()
                          else if (_error != null)
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.sync_problem_rounded),
                              label: Text(_error!),
                            )
                          else if (progress != null) ...[
                            Text(
                              '${persianDigits(progress.completed)} کار انجام‌شده · ${persianDigits(progress.xp)} امتیاز',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            LinearProgressIndicator(
                              value: (progress.levelXp / 100).clamp(0, 1),
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                              semanticsLabel:
                                  'رشد تا سطح بعد، ${persianDigits(progress.levelXp)} از ۱۰۰',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${persianDigits(100 - progress.levelXp)} امتیاز تا سطح بعد',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ] else
                            const Text(
                              'با انجام کارها، مسیر رشدتان را بسازید.',
                              textAlign: TextAlign.center,
                            ),
                          const SizedBox(height: 24),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final target in [1, 5, 10, 25, 50])
                                Expanded(
                                  child: Semantics(
                                    label:
                                        '${persianDigits(target)} کار انجام‌شده، ${completed != null && completed >= target ? "شکفته" : "در انتظار رشد"}',
                                    excludeSemantics: true,
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          height: 48,
                                          child: Icon(
                                            completed != null &&
                                                    completed >= target
                                                ? Icons.local_florist_rounded
                                                : Icons.lock_outline_rounded,
                                            size:
                                                completed != null &&
                                                    completed >= target
                                                ? 28
                                                : 20,
                                            color:
                                                completed != null &&
                                                    completed >= target
                                                ? c.primary
                                                : c.onSurfaceVariant,
                                          ),
                                        ),
                                        Text(
                                          '${persianDigits(target)} کار',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: c.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                      final next = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'قدم بعدی',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: widget.onTasks,
                                child: const Text('همهٔ کارها'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!_loading && _tasks.isEmpty) ...[
                            Text(
                              'جا برای یک شروع تازه هست.',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'یک کار کوچک انتخاب کن؛ همین کافی است.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: widget.onTasks,
                              icon: const Icon(Icons.add),
                              label: const Text('افزودن اولین کار'),
                            ),
                          ],
                          for (final task in _tasks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: c.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                child: ListTile(
                                  contentPadding:
                                      const EdgeInsetsDirectional.fromSTEB(
                                        12,
                                        8,
                                        8,
                                        8,
                                      ),
                                  leading: IconButton(
                                    tooltip: 'انجام «${task.title}»',
                                    onPressed: _busyTasks.contains(task.id)
                                        ? null
                                        : () => _complete(task),
                                    icon: Icon(
                                      Icons.radio_button_unchecked_rounded,
                                      color: task.priority.colorIn(context),
                                    ),
                                  ),
                                  title: Text(
                                    task.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => widget.onProject(task.projectId),
                                  trailing: IconButton(
                                    tooltip: 'تمرکز روی این کار',
                                    onPressed: () => widget.onFocus(task.title),
                                    icon: const Icon(
                                      Icons.play_circle_outline_rounded,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 28),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.hourglass_top_rounded,
                                    color: c.onSecondaryContainer,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'یک گوشهٔ آرام برای تمرکز',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: c.onSecondaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'یک کار، چند دقیقه، بدون عجله.',
                                    style: TextStyle(
                                      color: c.onSecondaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () => widget.onFocus(
                                      _tasks.firstOrNull?.title,
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('شروع یک جلسه'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                      if (size.maxWidth > 650) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: scene),
                            const SizedBox(width: 40),
                            Expanded(flex: 4, child: next),
                          ],
                        );
                      }
                      return Column(
                        children: [scene, const SizedBox(height: 32), next],
                      );
                    },
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
