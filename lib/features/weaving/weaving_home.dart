import 'package:farash/app/atelier.dart';
import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/weaving/woven_rug.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/priority_color.dart';

class WeavingHome extends StatefulWidget {
  const WeavingHome({
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
  State<WeavingHome> createState() => _WeavingHomeState();
}

class _WeavingHomeState extends State<WeavingHome> with WidgetsBindingObserver {
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
          error = 'پیشرفت بافت دریافت نشد. برای تلاش دوباره لمس کنید.';
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
        _error = 'اطلاعات فرش دریافت نشد. برای تلاش دوباره لمس کنید.';
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
          content: const Text('یک رج جلوتر. کار انجام شد.'),
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

  void _showCollection(int count) {
    final direction = Directionality.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => Directionality(
        textDirection: direction,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'فرش‌های من',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: 'بستن',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (count == 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'اولین فرشت با ۵۰ کارِ انجام‌شده کامل می‌شود.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (count == 1) ...[
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * .35,
                        child: const RugPattern(rows: 50),
                      ),
                      const SizedBox(height: 16),
                      const Text('فرش ۱'),
                    ] else
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * .45,
                        child: GridView.builder(
                          itemCount: count,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                mainAxisSpacing: 24,
                                crossAxisSpacing: 24,
                                childAspectRatio: .6,
                              ),
                          itemBuilder: (context, index) => Column(
                            children: [
                              Expanded(
                                child: RugPattern(rows: 50, design: index),
                              ),
                              const SizedBox(height: 8),
                              Text('فرش ${persianDigits(index + 1)}'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final progress = _progress;
    final completed = progress?.completed;
    final weave = completed == null ? null : WeaveProgress(completed);
    final stage = weave == null
        ? 'فرشِ روزهای تو'
        : 'فرش شمارهٔ ${persianDigits(weave.rugs + 1)}';
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        key: const PageStorageKey('weaving-scroll'),
        slivers: [
          SliverAppBar(
            title: const Text('فرشٔ من'),
            floating: true,
            actions: [
              IconButton(
                tooltip: 'تازه‌سازی فرش',
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
                                  'گره‌گره، رو به جلو.',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (progress != null)
                                Chip(
                                  avatar: const Icon(
                                    Icons.auto_awesome_rounded,
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
                            'هر کار، یک رج؛ هر روز، نقش تازه.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                          WovenRug(height: size.maxWidth > 650 ? 320 : 250),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: ThreadRule(),
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
                                  'پیشرفت تا سطح بعد، ${persianDigits(progress.levelXp)} از ۱۰۰',
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
                              'با انجام کارها، فرش خودت را بباف.',
                              textAlign: TextAlign.center,
                            ),
                          if (weave != null) ...[
                            const SizedBox(height: 20),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: c.outlineVariant),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 58,
                                      height: 80,
                                      child: RugPattern(
                                        rows: weave.rows,
                                        design: weave.rugs,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${persianDigits(weave.rows)} رج از ۵۰ رج',
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'هر کارِ انجام‌شده یک رج می‌بافد.',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 8),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _showCollection(weave.rugs),
                                            icon: const Icon(
                                              Icons
                                                  .collections_bookmark_outlined,
                                              size: 18,
                                            ),
                                            label: Text(
                                              'فرش‌های من · ${persianDigits(weave.rugs)}',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
                                child: const Text('فهرست کارها'),
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
                          AtelierPanel(
                            color: c.secondaryContainer,
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
