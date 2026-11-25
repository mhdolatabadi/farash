import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/calendar/date_labels.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/projects/data/project.dart';
import 'package:menval/features/labels/application/labels_controller.dart';
import 'package:menval/features/search/filter_editor.dart';
import 'package:menval/features/search/search.dart';
import 'package:menval/features/tasks/application/tasks_controller.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/task_detail_sheet.dart';
import 'package:menval/features/tasks/presentation/task_tile.dart';

/// A live owner-scoped query, using the same task editor and completion API.
class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    super.key,
    required this.api,
    required this.tasks,
    required this.token,
    required this.projects,
    this.sections,
    this.labels,
    this.filters,
    this.initialFilter,
  });
  final SearchApi api;

  /// The account's saved filters; the page makes its own when null.
  final FiltersController? filters;

  /// Opens the page with this filter's query, sort and grouping.
  final SavedFilter? initialFilter;
  final TasksApi tasks;
  final SectionsApi? sections;
  final LabelsController? labels;
  final String? Function() token;
  final List<Project> Function() projects;
  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  final query = TextEditingController();
  List<Task> tasks = [];
  late final FiltersController filters =
      widget.filters ?? FiltersController(api: widget.api, token: widget.token);
  late SavedFilter? applied = widget.initialFilter;
  late String sort = widget.initialFilter?.sort ?? 'due';
  late String group = widget.initialFilter?.groupBy ?? 'none';
  bool completed = false, loading = false, busy = false, more = false;
  String? error;
  int generation = 0, nextOffset = 0;
  String activeQuery = '';

  @override
  void initState() {
    super.initState();
    query.text = widget.initialFilter?.query ?? '';
    filters.addListener(_filtersChanged);
    filters.load();
    search();
  }

  @override
  void dispose() {
    generation++;
    filters.removeListener(_filtersChanged);
    if (widget.filters == null) filters.dispose();
    query.dispose();
    super.dispose();
  }

  String get token {
    final value = widget.token();
    if (value == null) throw StateError('برای جست‌وجو دوباره وارد شوید.');
    return value;
  }

  void _filtersChanged() {
    if (!mounted) return;
    // Keep the applied filter's name current; drop it once it is deleted.
    setState(() => applied = filters.byId(applied?.id));
  }

  /// Runs [filter]'s query with its sort and grouping.
  void apply(SavedFilter filter) {
    query.text = filter.query;
    setState(() {
      applied = filter;
      sort = filter.sort;
      group = filter.groupBy;
    });
    search();
  }

  Future<void> search({bool next = false}) async {
    final serial = ++generation;
    final requested = next ? activeQuery : query.text.trim();
    final offset = next ? nextOffset : 0;
    final selectedSort = sort;
    final includeDone = completed;
    setState(() {
      loading = true;
      error = null;
      if (!next) tasks = [];
    });
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    try {
      final path = Uri(
        path: '/api/v1/search',
        queryParameters: {
          'q': requested,
          'today': today,
          'sort': selectedSort,
          'completed': '$includeDone',
          'limit': '50',
          'offset': '$offset',
        },
      ).toString();
      final result = SearchPage.fromJson(
        await widget.api.searchRequest(token, 'GET', path),
      );
      if (!mounted || generation != serial) return;
      setState(() {
        tasks = next
            ? [
                ...tasks,
                ...result.tasks.where(
                  (t) => !tasks.any((old) => old.id == t.id),
                ),
              ]
            : result.tasks;
        nextOffset = offset + result.tasks.length;
        activeQuery = requested;
        more = result.hasMore;
        loading = false;
      });
    } catch (e) {
      if (!mounted || generation != serial) return;
      setState(() {
        loading = false;
        error = e is ApiException && e.statusCode == 400
            ? 'عبارت فیلتر معتبر نیست. راهنمای جست‌وجو را ببینید.'
            : 'جست‌وجو انجام نشد؛ اتصال و ورود به حساب را بررسی و دوباره تلاش کنید.';
      });
    }
  }

  Future<void> toggle(Task task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (task.isCompleted) {
        await widget.tasks.reopenTask(token, task.id);
      } else {
        await widget.tasks.closeTask(token, task.id);
      }
      if (mounted) await search();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'تغییر کار تأیید نشد. دوباره تلاش کنید.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Task task) async {
    if (busy) return;
    final requestToken = widget.token();
    setState(() => busy = true);
    final controller = TasksController(
      api: widget.tasks,
      sectionsApi: widget.sections,
      token: widget.token,
      projectId: task.projectId,
    );
    try {
      // Search results do not contain the project's sections or child rows.
      // Load the same complete context used by ordinary task-list editors.
      await controller.setShowCompleted(true);
      if (!mounted || widget.token() != requestToken) return;
      final current = controller.taskById(task.id);
      if (controller.error != null || current == null) {
        setState(() => error = 'جزئیات کار دریافت نشد؛ دوباره تلاش کنید.');
        return;
      }
      await showTaskDetailSheet(
        context,
        controller: controller,
        task: current,
        projects: widget.projects(),
        labels: widget.labels,
      );
      if (mounted) await search();
    } finally {
      controller.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  List<String> get _projectNames => [
    for (final p in widget.projects())
      if (!p.isInbox) p.name,
  ];

  List<String> get _labelNames => [
    for (final l in widget.labels?.labels ?? const []) l.name,
  ];

  /// Saves the current query as a new filter, or edits [filter].
  Future<void> save([SavedFilter? filter]) async {
    if (busy) return;
    final saved = await showFilterEditor(
      context,
      controller: filters,
      filter: filter,
      initialQuery: query.text.trim(),
      initialSort: sort,
      initialGroup: group,
      projectNames: _projectNames,
      labelNames: _labelNames,
    );
    if (mounted && saved != null) apply(saved);
  }

  Future<void> remove(SavedFilter filter) async {
    if (busy) return;
    if (!await confirmFilterDelete(context, filter) || !mounted) return;
    setState(() => busy = true);
    try {
      await filters.delete(filter);
    } catch (_) {
      if (mounted) setState(() => error = 'فیلتر حذف نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        applied?.name ?? 'جست‌وجو و فیلترها',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (applied case final filter?)
          IconButton(
            tooltip: 'ویرایش فیلتر',
            onPressed: busy ? null : () => save(filter),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            // Controls keep the gutter; result rows run edge to edge and
            // carry it themselves, like every other task list.
            children: [
              for (final child in <Widget>[
                TextField(
                  controller: query,
                  autofocus: true,
                  maxLength: 1000,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => search(),
                  decoration: InputDecoration(
                    labelText: 'جست‌وجوی کار یا عبارت فیلتر',
                    hintText: 'مثلاً امروز & p1',
                    counterText: '',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'پاک کردن عبارت',
                      onPressed: () {
                        query.clear();
                        search();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: loading ? null : () => search(),
                      icon: const Icon(Icons.search),
                      label: const Text('جست‌وجو'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => save(),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('ذخیرهٔ فیلتر'),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width < 420
                          ? MediaQuery.sizeOf(context).width - Space.gutter * 2
                          : 240,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: sort,
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => sort = value);
                            search();
                          }
                        },
                        items: [
                          for (final choice in filterSorts)
                            DropdownMenuItem(
                              value: choice.$1,
                              child: Text(
                                'مرتب‌سازی: ${choice.$2}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width < 420
                          ? MediaQuery.sizeOf(context).width - Space.gutter * 2
                          : 240,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: group,
                        onChanged: (value) {
                          if (value != null) setState(() => group = value);
                        },
                        items: [
                          for (final choice in filterGroups)
                            DropdownMenuItem(
                              value: choice.$1,
                              child: Text(
                                'گروه: ${choice.$2}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    FilterChip(
                      label: const Text('کارهای انجام‌شده'),
                      selected: completed,
                      onSelected: (value) {
                        setState(() => completed = value);
                        search();
                      },
                    ),
                  ],
                ),
                ExpansionTile(
                  title: const Text('راهنمای جست‌وجو'),
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  childrenPadding: const EdgeInsets.only(bottom: Space.lg),
                  children: const [
                    Padding(
                      padding: EdgeInsets.zero,
                      child: Text(
                        'متن عنوان، توضیحات و نظرها، امروز، دیرشده، "7 days"، "no date"، p1 تا p4، #نام‌پروژه، ##پروژه‌با‌زیرپروژه‌ها و @برچسب. برای ترکیب از &، |، ! و پرانتز استفاده کنید. نام‌های چندکلمه‌ای را در گیومه بگذارید. تاریخ‌ها با روز فعلی دستگاه محاسبه می‌شوند.',
                      ),
                    ),
                  ],
                ),
                if (filters.error != null) ...[
                  const Text('فیلترهای ذخیره‌شده دریافت نشدند.'),
                  TextButton(
                    onPressed: filters.load,
                    child: const Text('دریافت دوبارهٔ فیلترها'),
                  ),
                ],
                if (filters.filters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'فیلترهای من',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in filters.filters)
                        InputChip(
                          avatar: Icon(
                            Icons.filter_alt_outlined,
                            color: filterSwatch(filter.color),
                          ),
                          label: Text(filter.name),
                          selected: filter.id == applied?.id,
                          showCheckmark: false,
                          onPressed: () => apply(filter),
                          onDeleted: busy ? null : () => remove(filter),
                          deleteButtonTooltipMessage:
                              'حذف فیلتر ${filter.name}',
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.sm),
                const Divider(),
                const SizedBox(height: Space.lg),
                if (loading)
                  const LinearProgressIndicator(
                    semanticsLabel: 'دریافت نتیجهٔ جست‌وجو',
                  ),
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () => search(),
                    child: const Text('تلاش دوباره'),
                  ),
                ],
                if (!loading && error == null && tasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'کاری با این عبارت پیدا نشد. عبارت یا فیلتر را تغییر دهید.',
                    ),
                  ),
                if (tasks.isNotEmpty)
                  Text(
                    '${persianDigits(tasks.length)} کار دریافت شد',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  child: child,
                ),
              for (final (title, rows) in groupTasks(
                tasks,
                group,
                projects: widget.projects(),
                labelName: (id) => widget.labels?.byId(id)?.name,
              )) ...[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.md,
                      Space.gutter,
                      Space.xs,
                    ),
                    child: Text(
                      '$title · ${persianDigits(rows.length)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter - 2,
                    Space.sm,
                    Space.gutter - 2,
                    0,
                  ),
                  child: SoftWell(
                    child: Column(
                      children: [
                        for (final task in rows)
                          IgnorePointer(
                            ignoring: busy,
                            child: TaskTile(
                              task: task,
                              dense: true,
                              divider: task != rows.last,
                              onToggle: () => toggle(task),
                              onOpen: () => open(task),
                              tag: Text(
                                widget
                                        .projects()
                                        .where((p) => p.id == task.projectId)
                                        .firstOrNull
                                        ?.name ??
                                    'پروژه',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (more && !loading && error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => search(next: true),
                      child: const Text('نتایج بیشتر'),
                    ),
                  ),
                ),
              const SizedBox(height: Space.xl),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks before deleting [filter]; its tasks stay.
Future<bool> confirmFilterDelete(
  BuildContext context,
  SavedFilter filter,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف فیلتر «${filter.name}»؟'),
        content: const Text('کارها حذف نمی‌شوند.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف فیلتر'),
          ),
        ],
      ),
    ) ==
    true;

/// Splits [tasks] by [group], keeping their order inside each group. A null
/// title means one ungrouped list.
List<(String?, List<Task>)> groupTasks(
  List<Task> tasks,
  String group, {
  required List<Project> projects,
  required String? Function(String id) labelName,
  DateTime? today,
}) {
  if (tasks.isEmpty) return const [];
  final day = dayOf(today ?? DateTime.now());
  final keyed = <(int, String), List<Task>>{};
  void put(int rank, String title, Task task) =>
      (keyed[(rank, title)] ??= []).add(task);
  for (final task in tasks) {
    switch (group) {
      case 'date':
        final due = task.due;
        if (due == null) {
          put(5, 'بی‌تاریخ', task);
        } else {
          final offset = daysBetween(day, due.day);
          final (rank, title) = switch (offset) {
            < 0 => (0, 'دیرشده'),
            0 => (1, 'امروز'),
            1 => (2, 'فردا'),
            < 7 => (3, 'هفت روز آینده'),
            _ => (4, 'بعدتر'),
          };
          put(rank, title, task);
        }
      case 'priority':
        put(task.priority.level, task.priority.label, task);
      case 'project':
        final index = projects.indexWhere((p) => p.id == task.projectId);
        put(
          index < 0 ? projects.length : index,
          index < 0 ? 'پروژه' : projects[index].name,
          task,
        );
      case 'label':
        final names = [for (final id in task.labelIds) ?labelName(id)]..sort();
        if (names.isEmpty) {
          put(1, 'بدون برچسب', task);
        } else {
          for (final name in names) {
            put(0, '@$name', task);
          }
        }
      default:
        return [(null, tasks)];
    }
  }
  final keys = keyed.keys.toList()
    ..sort((a, b) {
      final rank = a.$1.compareTo(b.$1);
      return rank != 0 ? rank : a.$2.compareTo(b.$2);
    });
  return [for (final k in keys) (k.$2, keyed[k]!)];
}
