import 'package:flutter/material.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/app/surfaces.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/application/tasks_controller.dart';
import 'package:farash/features/tasks/presentation/task_detail_sheet.dart';
import 'package:farash/features/tasks/presentation/task_tile.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'scrum.dart';
import 'scrum_forms.dart';

class ProjectWorkspace extends StatefulWidget {
  const ProjectWorkspace({
    super.key,
    required this.project,
    required this.api,
    required this.tasks,
    required this.token,
    required this.projects,
    required this.simple,
  });
  final Project project;
  final ScrumApi api;
  final TasksApi tasks;
  final String? Function() token;
  final List<Project> Function() projects;
  final Widget simple;
  @override
  State<ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends State<ProjectWorkspace> {
  late final c = ScrumController(
    api: widget.api,
    tasks: widget.tasks,
    token: widget.token,
    projectId: widget.project.id,
  );
  final capture = TextEditingController();
  int tab = 0;
  String column = 'todo';
  String? reportId;
  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    capture.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> open(ScrumItem item) async {
    final tasks = TasksController(
      api: widget.tasks,
      token: widget.token,
      projectId: widget.project.id,
    );
    try {
      await showTaskDetailSheet(
        context,
        controller: tasks,
        task: item.task,
        projects: widget.projects(),
      );
      await c.load();
    } finally {
      tasks.dispose();
    }
  }

  Widget itemTile(ScrumItem item, {bool drag = false}) {
    final tile = Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskTile(
            task: item.task,
            dense: true,
            onToggle: () {
              if (!c.busy) {
                c.move(item, item.task.isCompleted ? 'todo' : 'done');
              }
            },
            onOpen: () => open(item),
            divider: false,
            trailing: PopupMenuButton<String>(
              tooltip: 'گزینه‌های اسکرام',
              enabled: !c.busy,
              onSelected: (v) {
                if (v == 'edit') {
                  editScrumItem(context, c, item);
                } else {
                  c.move(item, v);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('برآورد و اسپرینت'),
                ),
                for (final e in scrumColumns.entries)
                  PopupMenuItem(
                    value: e.key,
                    child: Text('انتقال به ${e.value}'),
                  ),
              ],
            ),
          ),
          Padding(
            // Under the title, on the row's content keyline.
            padding: const EdgeInsetsDirectional.only(
              start: Space.keyline,
              end: Space.md,
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(scrumKinds[item.kind]!),
                Text(
                  item.points == null
                      ? 'بدون برآورد'
                      : '${persianDigits(item.points!)} امتیاز داستان',
                ),
                if (item.acceptance.isNotEmpty)
                  const Tooltip(
                    message: 'معیار پذیرش دارد',
                    child: Icon(Icons.fact_check_outlined, size: 18),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!drag || c.busy) return tile;
    return LongPressDraggable<ScrumItem>(
      data: item,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(item.task.title),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final d = c.data;
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.xs,
                vertical: Space.xs,
              ),
              child: Row(
                children: [
                  if (Scaffold.maybeOf(context)?.hasDrawer ?? false)
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).openAppDrawerTooltip,
                      onPressed: Scaffold.of(context).openDrawer,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.md,
                      ),
                      child: Text(
                        widget.project.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'روش مدیریت پروژه',
                    enabled: d != null && !c.busy && !widget.project.isArchived,
                    initialValue: d?.method,
                    onSelected: (method) =>
                        c.write('PATCH', '', {'method': method}),
                    itemBuilder: (_) => [
                      for (final e in projectMethods.entries)
                        CheckedPopupMenuItem(
                          value: e.key,
                          checked: d?.method == e.key,
                          child: Text(e.value),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(projectMethods[d?.method] ?? 'روش کار'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'تازه‌کردن پروژه',
                    onPressed: c.busy ? null : c.load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: Text(
                  c.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: d == null || d.method == 'simple'
                  ? widget.simple
                  : LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          Space.gutter,
                          Space.sm,
                          Space.gutter,
                          Space.xxl,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1140),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (d.method == 'scrum')
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final e in [
                                        (0, 'بک‌لاگ'),
                                        (1, 'برد اسپرینت'),
                                        (2, 'گزارش و مرور'),
                                      ])
                                        ChoiceChip(
                                          label: Text(e.$2),
                                          selected: tab == e.$1,
                                          onSelected: (_) =>
                                              setState(() => tab = e.$1),
                                        ),
                                    ],
                                  ),
                                const SizedBox(height: Space.lg),
                                if (d.method == 'kanban')
                                  board(d, box.maxWidth, all: true)
                                else if (tab == 0)
                                  backlog(d)
                                else if (tab == 1)
                                  board(d, box.maxWidth)
                                else
                                  reports(d),
                                if (tab != 2 || d.method == 'kanban') ...[
                                  const SizedBox(height: Space.xl),
                                  const Divider(),
                                  const SizedBox(height: Space.lg),
                                  TextField(
                                    controller: capture,
                                    enabled:
                                        !c.busy && !widget.project.isArchived,
                                    buildCounter: scrumCounter,
                                    maxLength: 500,
                                    decoration: InputDecoration(
                                      labelText: 'کار تازه در بک‌لاگ',
                                      suffixIcon: IconButton(
                                        tooltip: 'افزودن کار',
                                        onPressed: c.busy ? null : add,
                                        icon: const Icon(Icons.add),
                                      ),
                                    ),
                                    onSubmitted: (_) => add(),
                                  ),
                                ],
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
    },
  );
  Future<void> add() async {
    if (capture.text.trim().isEmpty) return;
    if (await c.add(capture.text) && mounted) capture.clear();
  }

  Widget backlog(ScrumData d) {
    final unassigned = d.items
        .where(
          (i) =>
              !i.task.isCompleted &&
              (i.sprintId == null ||
                  !d.sprints.any(
                    (s) => s.id == i.sprintId && s.state != 'closed',
                  )),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: c.busy || widget.project.isArchived
                ? null
                : () => editSprint(context, c),
            icon: const Icon(Icons.add),
            label: const Text('اسپرینت تازه'),
          ),
        ),
        for (final sprint in d.sprints.where((s) => s.state != 'closed')) ...[
          const SizedBox(height: Space.xl),
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sprint.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sprint.goal.isNotEmpty) Text(sprint.goal),
                const SizedBox(height: Space.xs),
                // Dates and load on one muted line.
                Builder(
                  builder: (_) {
                    final items = d.items
                        .where((i) => i.sprintId == sprint.id)
                        .toList();
                    final points = items.fold<int>(
                      0,
                      (n, i) => n + (i.points ?? 0),
                    );
                    final over =
                        sprint.capacity != null && points > sprint.capacity!;
                    return Text(
                      '${date(context, sprint.start)} تا ${date(context, sprint.end)} · '
                      '${persianDigits(items.length)} کار · ${persianDigits(points)} امتیاز'
                      '${sprint.capacity == null ? '' : ' از ظرفیت ${persianDigits(sprint.capacity!)}'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: over
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
                const SizedBox(height: Space.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (sprint.state == 'planned') ...[
                      FilledButton(
                        onPressed:
                            c.busy ||
                                d.active != null ||
                                widget.project.isArchived
                            ? null
                            : () => startSprint(sprint),
                        child: const Text('شروع اسپرینت'),
                      ),
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => editSprint(context, c, sprint: sprint),
                        child: const Text('ویرایش برنامه'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: c.busy
                            ? null
                            : () => sprintNotes(
                                context,
                                c,
                                sprint,
                                closing: true,
                              ),
                        child: const Text('پایان اسپرینت'),
                      ),
                    TextButton(
                      onPressed: c.busy
                          ? null
                          : () => sprintNotes(context, c, sprint),
                      child: const Text('مرور و رترو'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (d.items.any((i) => i.sprintId == sprint.id))
            well([
              for (final item in d.items.where((i) => i.sprintId == sprint.id))
                itemTile(item),
            ]),
        ],
        const SizedBox(height: 24),
        Text('بک‌لاگ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (unassigned.isEmpty)
          const Text(
            'کار تازه را پایین اضافه کنید؛ از گزینه‌های هر کار، برآورد و اسپرینتش را تعیین کنید.',
          ),
        if (unassigned.isNotEmpty)
          well([for (final item in unassigned) itemTile(item)]),
        if (d.items.any((i) => i.task.isCompleted && i.sprintId == null))
          ExpansionTile(
            title: const Text('انجام‌شده‌های بک‌لاگ'),
            children: [
              for (final item in d.items.where(
                (i) => i.task.isCompleted && i.sprintId == null,
              ))
                itemTile(item),
            ],
          ),
      ],
    );
  }

  Future<void> startSprint(ScrumSprint sprint) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('شروع این اسپرینت؟'),
        content: const Text(
          'کارهای باز این نوبت ثبت می‌شوند و برآوردشان تا پایان ثابت می‌ماند. تغییر محدوده در گزارش ثبت می‌شود. تاریخ‌های برنامه‌ریزی‌شده، تایمر پایان خودکار نیستند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('شروع'),
          ),
        ],
      ),
    );
    if (yes == true) await c.write('POST', '/sprints/${sprint.id}/start', {});
  }

  Widget board(ScrumData d, double width, {bool all = false}) {
    if (!all && d.active == null) {
      return const Text(
        'اسپرینت فعالی ندارید. در بک‌لاگ کار انتخاب کنید و اسپرینت را شروع کنید.',
      );
    }
    final items = d.items
        .where(
          (i) =>
              (all || i.kind != 'epic') &&
              (all
                  ? (!i.task.isCompleted || i.sprintId == null)
                  : i.sprintId == d.active!.id),
        )
        .toList();
    final wide = width >= 940;
    Widget lane(String key) => DragTarget<ScrumItem>(
      onWillAcceptWithDetails: (_) => !c.busy,
      onAcceptWithDetails: (v) => c.move(v.data, key),
      builder: (context, candidates, rejected) => Padding(
        padding: const EdgeInsets.all(4),
        child: SoftWell(
          child: ColoredBox(
            color: candidates.isEmpty
                ? Colors.transparent
                : Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${scrumColumns[key]} · ${persianDigits(items.where((i) => i.column == key).length)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!items.any((i) => i.column == key))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('کاری در این ستون نیست.'),
                    ),
                  for (final item in items.where((i) => i.column == key))
                    itemTile(item, drag: wide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!all) ...[
          Text(d.active!.name, style: Theme.of(context).textTheme.titleLarge),
          Text(d.active!.goal),
          const SizedBox(height: 16),
        ],
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in scrumColumns.keys) Expanded(child: lane(e)),
            ],
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in scrumColumns.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: column == e.key,
                  onSelected: (_) => setState(() => column = e.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          lane(column),
        ],
      ],
    );
  }

  Widget reports(ScrumData d) {
    final choices = d.sprints.where((s) => s.state != 'planned').toList();
    if (choices.isEmpty) {
      return const Text(
        'با شروع نخستین اسپرینت، گزارش واقعی محدوده و کار باقی‌مانده اینجا شکل می‌گیرد.',
      );
    }
    final sprint =
        choices.where((s) => s.id == reportId).firstOrNull ??
        d.active ??
        choices.first;
    final events = d.events.where((e) => e['sprint_id'] == sprint.id).toList();
    final scope = d.scope.where((e) => e['sprint_id'] == sprint.id).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: sprint.id,
          key: ValueKey(sprint.id),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'اسپرینت'),
          items: [
            for (final s in choices)
              DropdownMenuItem(
                value: s.id,
                child: Text(
                  '${s.name}${s.state == 'active' ? ' · فعال' : ' · بسته‌شده'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => reportId = v),
        ),
        const SizedBox(height: 16),
        if (sprint.goal.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              sprint.goal,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        _Stats(
          stats: [
            (
              'انجام‌شده',
              '${persianDigits(sprint.number('done_count'))} از ${persianDigits(sprint.number('scope_count'))} کار',
            ),
            (
              'امتیاز انجام‌شده',
              '${persianDigits(sprint.number('done_points'))} از ${persianDigits(sprint.number('scope_points'))}',
            ),
            (
              'تعهد آغاز',
              '${persianDigits(sprint.number('committed_count'))} کار · ${persianDigits(sprint.number('committed_points'))} امتیاز',
            ),
            (
              'زمان ثبت‌شده',
              trackedTime(Duration(seconds: sprint.number('tracked_seconds'))),
            ),
            (
              'بدون برآورد',
              '${persianDigits(sprint.number('unestimated'))} کار',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'کار باقی‌مانده',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'دربارهٔ گزارش',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('دربارهٔ گزارش'),
                  content: const Text(
                    'زمان فقط برای کارهای محدودهٔ این اسپرینت و در بازهٔ اجرای آن شمرده می‌شود. امتیازِ بدون برآورد، صفرِ تخمینی نیست؛ شمار کارها را هم ببینید.\n\nنمودار از تغییرات ثبت‌شده است؛ خط ایده‌آل یا دادهٔ حدسی ندارد.\n\nسرعت، خروجی واقعی هر نوبت است؛ معیار مقایسه یا امتیاز دادن به افراد نیست.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SoftTile(
          padding: const EdgeInsets.all(12),
          child: Burndown(events: events),
        ),
        const SizedBox(height: 24),
        Text(
          'سرعت اسپرینت‌های بسته‌شده',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (d.sprints.any((s) => s.state == 'closed')) ...[
          const SizedBox(height: 8),
          well([
            for (final s in d.sprints.where((s) => s.state == 'closed'))
              ListTile(
                title: Text(s.name),
                subtitle: Text(
                  '${persianDigits(s.number('done_points'))} امتیاز داستان · ${persianDigits(s.number('done_count'))} کار',
                ),
              ),
          ]),
        ],
        const SizedBox(height: 20),
        Text('مرور و رترو', style: Theme.of(context).textTheme.titleLarge),
        Text(sprint.review.isEmpty ? 'مرور هنوز نوشته نشده.' : sprint.review),
        const SizedBox(height: 8),
        Text(
          sprint.retro.isEmpty
              ? 'رترو اختیاری است: چه چیزی را دفعهٔ بعد عوض می‌کنید؟'
              : sprint.retro,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: c.busy ? null : () => sprintNotes(context, c, sprint),
            child: const Text('نوشتن مرور و رترو'),
          ),
        ),
        const SizedBox(height: 20),
        Text('محدودهٔ ثبت‌شده', style: Theme.of(context).textTheme.titleLarge),
        if (scope.isNotEmpty) const SizedBox(height: 8),
        if (scope.isNotEmpty)
          well([
            for (final row in scope)
              ListTile(
                leading: Icon(
                  row['removed_at'] != null
                      ? Icons.remove_circle_outline
                      : row['completed'] == true
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                ),
                title: Text(row['title'] as String),
                subtitle: Text(
                  row['removed_at'] != null
                      ? 'از محدوده خارج شد'
                      : row['points'] == null
                      ? 'بدون برآورد'
                      : '${persianDigits(row['points'])} امتیاز داستان',
                ),
              ),
          ]),
      ],
    );
  }

  /// A run of rows sunk into the soft ground.
  Widget well(List<Widget> children) => SoftWell(
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

String date(BuildContext context, DateTime value) =>
    formatDate(value, CalendarScope.of(context), alwaysYear: true);

class Burndown extends StatefulWidget {
  const Burndown({super.key, required this.events});
  final List<Map<String, dynamic>> events;
  @override
  State<Burndown> createState() => _BurndownState();
}

class _BurndownState extends State<Burndown> {
  bool points = false;
  @override
  Widget build(BuildContext context) {
    final key = points ? 'remaining_points' : 'remaining_count';
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('شمار کارها'),
              selected: !points,
              onSelected: (_) => setState(() => points = false),
            ),
            ChoiceChip(
              label: const Text('امتیاز داستان'),
              selected: points,
              onSelected: (_) => setState(() => points = true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _BurnPainter(widget.events, key, color),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('زمان تغییر')),
              const DataColumn(label: Text('محدوده')),
              const DataColumn(label: Text('باقی‌مانده')),
            ],
            rows: [
              for (final e in widget.events)
                DataRow(
                  cells: [
                    DataCell(
                      Text(
                        '${date(context, DateTime.parse(e['at'] as String).toLocal())} ${persianDigits(TimeOfDay.fromDateTime(DateTime.parse(e['at'] as String).toLocal()).format(context))}',
                      ),
                    ),
                    DataCell(
                      Text(
                        persianDigits(
                          e[points ? 'scope_points' : 'scope_count'],
                        ),
                      ),
                    ),
                    DataCell(Text(persianDigits(e[key]))),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BurnPainter extends CustomPainter {
  _BurnPainter(this.events, this.key, this.color);
  final List<Map<String, dynamic>> events;
  final String key;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;
    final first = DateTime.parse(
      events.first['at'] as String,
    ).millisecondsSinceEpoch;
    final last = DateTime.parse(
      events.last['at'] as String,
    ).millisecondsSinceEpoch;
    final max = events.fold<int>(
      1,
      (n, e) => (e[key] as int) > n ? e[key] as int : n,
    );
    final path = Path();
    Offset? previous;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final e in events) {
      final x = last == first
          ? size.width / 2
          : (DateTime.parse(e['at'] as String).millisecondsSinceEpoch - first) /
                    (last - first) *
                    (size.width - 12) +
                6;
      final y = size.height - 8 - (e[key] as int) / max * (size.height - 16);
      final p = Offset(x, y);
      if (previous == null) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, previous.dy);
        path.lineTo(x, y);
      }
      canvas.drawCircle(p, 3, Paint()..color = color);
      previous = p;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BurnPainter old) =>
      old.events != events || old.key != key || old.color != color;
}

/// A sprint's numbers as small raised tiles, two or three to a row.
class _Stats extends StatelessWidget {
  const _Stats({required this.stats});
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = box.maxWidth >= 600 * scale
            ? 3
            : box.maxWidth >= 280 * scale
            ? 2
            : 1;
        final width = (box.maxWidth - Space.md * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final (label, value) in stats)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '$label: $value',
                  excludeSemantics: true,
                  child: SoftTile(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
