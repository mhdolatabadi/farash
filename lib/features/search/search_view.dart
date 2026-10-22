import 'package:flutter/material.dart';
import 'package:farash/app/atelier.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/search/search.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';

/// A live owner-scoped query, using the same task editor and completion API.
class SearchWorkspace extends StatefulWidget {
  const SearchWorkspace({
    super.key,
    required this.api,
    required this.tasks,
    required this.token,
    required this.projects,
    this.sections,
  });
  final SearchApi api;
  final TasksApi tasks;
  final SectionsApi? sections;
  final String? Function() token;
  final List<Project> Function() projects;
  @override
  State<SearchWorkspace> createState() => _SearchWorkspaceState();
}

class _SearchWorkspaceState extends State<SearchWorkspace> {
  final query = TextEditingController();
  List<Task> tasks = [];
  List<SavedFilter> filters = [];
  String sort = 'due';
  bool completed = false, loading = false, busy = false, more = false;
  String? error, filterError;
  int generation = 0, nextOffset = 0;
  String activeQuery = '';

  @override
  void initState() {
    super.initState();
    loadFilters();
    search();
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    super.dispose();
  }

  String get token {
    final value = widget.token();
    if (value == null) throw StateError('برای جست‌وجو دوباره وارد شوید.');
    return value;
  }

  Future<void> loadFilters() async {
    try {
      final result = await widget.api.searchRequest(
        token,
        'GET',
        '/api/v1/filters',
      );
      if (!mounted) return;
      setState(() {
        filters = [
          for (final f in result['filters'] as List<dynamic>)
            SavedFilter.fromJson(f as Map<String, dynamic>),
        ];
        filterError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => filterError = 'فیلترهای ذخیره‌شده دریافت نشدند.');
      }
    }
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
    final controller = TasksController(
      api: widget.tasks,
      sectionsApi: widget.sections,
      token: widget.token,
      projectId: task.projectId,
    );
    try {
      await showTaskDetailSheet(
        context,
        controller: controller,
        task: task,
        projects: widget.projects(),
      );
      if (mounted) await search();
    } finally {
      controller.dispose();
    }
  }

  Future<void> save() async {
    if (busy) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => const _FilterNameDialog(),
    );
    if (!mounted || picked == null) return;
    setState(() => busy = true);
    try {
      await widget.api.searchRequest(
        token,
        'POST',
        '/api/v1/filters',
        body: {
          'name': picked,
          'query': query.text.trim(),
          'sort': sort,
          'is_favorite': true,
          'color': '#98503D',
        },
      );
      if (mounted) await loadFilters();
    } catch (_) {
      if (mounted) setState(() => error = 'فیلتر ذخیره نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(SavedFilter filter) async {
    if (busy) return;
    final yes = await showDialog<bool>(
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
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.searchRequest(
        token,
        'DELETE',
        '/api/v1/filters/${Uri.encodeComponent(filter.id)}',
      );
      if (mounted) await loadFilters();
    } catch (_) {
      if (mounted) setState(() => error = 'فیلتر حذف نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('جست‌وجو و فیلترها')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
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
              const SizedBox(height: 12),
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
                    onPressed: busy ? null : save,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('ذخیرهٔ فیلتر'),
                  ),
                  DropdownButton<String>(
                    value: sort,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => sort = value);
                        search();
                      }
                    },
                    items: [
                      for (final choice in [
                        ('due', 'موعد'),
                        ('priority', 'اولویت'),
                        ('title', 'عنوان'),
                        ('project', 'پروژه'),
                      ])
                        DropdownMenuItem(
                          value: choice.$1,
                          child: Text('مرتب‌سازی: ${choice.$2}'),
                        ),
                    ],
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
                children: const [
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'متن عنوان و توضیحات، امروز، دیرشده، "no date"، p1 تا p4، #نام‌پروژه و @برچسب. برای ترکیب از &، |، ! و پرانتز استفاده کنید. نام‌های چندکلمه‌ای را در گیومه بگذارید. تاریخ‌ها با روز فعلی دستگاه محاسبه می‌شوند.',
                    ),
                  ),
                ],
              ),
              if (filterError != null) ...[
                Text(filterError!),
                TextButton(
                  onPressed: loadFilters,
                  child: const Text('دریافت دوبارهٔ فیلترها'),
                ),
              ],
              if (filters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'فیلترهای من',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in filters)
                      InputChip(
                        label: Text(filter.name),
                        onPressed: () {
                          query.text = filter.query;
                          setState(() => sort = filter.sort);
                          search();
                        },
                        onDeleted: busy ? null : () => remove(filter),
                        deleteButtonTooltipMessage: 'حذف فیلتر ${filter.name}',
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const ThreadRule(),
              const SizedBox(height: 16),
              if (loading)
                const LinearProgressIndicator(
                  semanticsLabel: 'دریافت نتیجهٔ جست‌وجو',
                ),
              if (error != null) ...[
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              for (final task in tasks)
                IgnorePointer(
                  ignoring: busy,
                  child: TaskTile(
                    task: task,
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
              if (more && !loading && error == null)
                TextButton(
                  onPressed: () => search(next: true),
                  child: const Text('نتایج بیشتر'),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FilterNameDialog extends StatefulWidget {
  const _FilterNameDialog();
  @override
  State<_FilterNameDialog> createState() => _FilterNameDialogState();
}

class _FilterNameDialogState extends State<_FilterNameDialog> {
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void submit() {
    if (name.text.trim().isNotEmpty) Navigator.pop(context, name.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ذخیرهٔ فیلتر'),
    content: TextField(
      controller: name,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'نام فیلتر'),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(onPressed: submit, child: const Text('ذخیره')),
    ],
  );
}
