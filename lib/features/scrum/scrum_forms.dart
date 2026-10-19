import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'scrum.dart';

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _date(BuildContext context, DateTime d) =>
    formatDate(d, CalendarScope.of(context), alwaysYear: true);
int? _integer(String s) => int.tryParse(
  s.trim().replaceAllMapped(
    RegExp('[۰-۹]'),
    (m) => '۰۱۲۳۴۵۶۷۸۹'.indexOf(m[0]!).toString(),
  ),
);

Future<void> editSprint(
  BuildContext context,
  ScrumController c, {
  ScrumSprint? sprint,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SprintEditor(c: c, sprint: sprint),
);

class _SprintEditor extends StatefulWidget {
  const _SprintEditor({required this.c, this.sprint});
  final ScrumController c;
  final ScrumSprint? sprint;
  @override
  State<_SprintEditor> createState() => _SprintEditorState();
}

class _SprintEditorState extends State<_SprintEditor> {
  late final name = TextEditingController(text: widget.sprint?.name ?? '');
  late final goal = TextEditingController(text: widget.sprint?.goal ?? '');
  late final capacity = TextEditingController(
    text: widget.sprint?.capacity?.toString() ?? '',
  );
  late DateTime start =
      widget.sprint?.start ?? DateUtils.dateOnly(DateTime.now());
  late DateTime end = widget.sprint?.end ?? start.add(const Duration(days: 13));
  final requestKey = timeKey();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    goal.dispose();
    capacity.dispose();
    super.dispose();
  }

  Future<void> pick(bool first) async {
    final picked = await showDuePicker(
      context,
      initial: TaskDates(due: TaskDue.onDay(first ? start : end)),
      dueOnly: true,
    );
    if (picked?.due != null && mounted)
      setState(() {
        if (first) {
          start = picked!.due!.day;
        } else {
          end = picked!.due!.day;
        }
      });
  }

  Future<void> save() async {
    final n = capacity.text.trim().isEmpty ? null : _integer(capacity.text);
    if (name.text.trim().isEmpty ||
        end.isBefore(start) ||
        end.difference(start).inDays > 90 ||
        capacity.text.trim().isNotEmpty && (n == null || n < 0 || n > 10000)) {
      setState(
        () => error = 'نام، بازهٔ حداکثر ۹۰ روز و ظرفیت نامنفی را بررسی کن.',
      );
      return;
    }
    setState(() => saving = true);
    final s = widget.sprint;
    final ok = await widget.c.write(
      s == null ? 'POST' : 'PATCH',
      s == null ? '/sprints' : '/sprints/${s.id}',
      {
        'request_key': requestKey,
        'name': name.text.trim(),
        'goal': goal.text,
        'starts_on': _day(start),
        'ends_on': _day(end),
        'capacity': n,
      },
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.c.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.sprint == null ? 'اسپرینت تازه' : 'برنامهٔ اسپرینت'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: name,
              enabled: !saving,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'نام اسپرینت'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: goal,
              enabled: !saving,
              maxLength: 4000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'هدف اسپرینت'),
            ),
            TextButton(
              onPressed: saving ? null : () => pick(true),
              child: Text('شروع برنامه: ${_date(context, start)}'),
            ),
            TextButton(
              onPressed: saving ? null : () => pick(false),
              child: Text('پایان برنامه: ${_date(context, end)}'),
            ),
            TextField(
              controller: capacity,
              enabled: !saving,
              keyboardType: TextInputType.number,
              maxLength: 5,
              decoration: const InputDecoration(
                labelText: 'ظرفیت پیشنهادی · امتیاز داستان',
                helperText: 'اختیاری؛ زمان برآوردشدهٔ کارها جداست.',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'در حال ذخیره…' : 'ذخیره'),
      ),
    ],
  );
}

Future<void> editScrumItem(
  BuildContext context,
  ScrumController c,
  ScrumItem item,
) => showDialog<void>(
  context: context,
  builder: (_) => _ItemEditor(c: c, item: item),
);

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({required this.c, required this.item});
  final ScrumController c;
  final ScrumItem item;
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late String kind = widget.item.kind;
  late String? sprintId =
      widget.c.data!.sprints.any(
        (s) => s.id == widget.item.sprintId && s.state != 'closed',
      )
      ? widget.item.sprintId
      : null;
  late final points = TextEditingController(
    text: widget.item.points?.toString() ?? '',
  );
  late final acceptance = TextEditingController(text: widget.item.acceptance);
  bool saving = false;
  String? error;
  bool get frozen => widget.c.data!.sprints.any(
    (s) => s.id == widget.item.sprintId && s.state == 'active',
  );
  @override
  void dispose() {
    points.dispose();
    acceptance.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final n = points.text.trim().isEmpty ? null : _integer(points.text);
    if (points.text.trim().isNotEmpty && (n == null || n < 0 || n > 1000) ||
        kind == 'epic' && sprintId != null) {
      setState(
        () =>
            error = 'امتیاز باید بین صفر و ۱۰۰۰ باشد. اپیک در بک‌لاگ می‌ماند.',
      );
      return;
    }
    setState(() => saving = true);
    final ok = await widget.c
        .write('PUT', '/items/${Uri.encodeComponent(widget.item.task.id)}', {
          'issue_type': kind,
          'points': n,
          'acceptance': acceptance.text,
          'sprint_id': sprintId,
          'stage': widget.item.stage,
        });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.c.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('برآورد و اسپرینت'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.task.title),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'نوع کار'),
              items: [
                for (final e in scrumKinds.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: saving ? null : (v) => setState(() => kind = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: points,
              enabled: !saving && !frozen,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: 'امتیاز داستان · اختیاری',
                helperText: frozen
                    ? 'برآورد داخل اسپرینت فعال ثابت می‌ماند.'
                    : 'بدون برآورد را خالی بگذار؛ امتیاز با ساعت فرق دارد.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: sprintId ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'اسپرینت'),
              items: [
                const DropdownMenuItem(value: '', child: Text('بک‌لاگ')),
                for (final s in widget.c.data!.sprints.where(
                  (s) => s.state != 'closed',
                ))
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.name}${s.state == 'active' ? ' · فعال' : ''}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: saving
                  ? null
                  : (v) => setState(() => sprintId = v == '' ? null : v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: acceptance,
              enabled: !saving,
              minLines: 3,
              maxLines: 8,
              maxLength: 20000,
              decoration: const InputDecoration(labelText: 'معیار پذیرش'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'در حال ذخیره…' : 'ذخیره'),
      ),
    ],
  );
}

Future<void> sprintNotes(
  BuildContext context,
  ScrumController c,
  ScrumSprint sprint, {
  bool closing = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _SprintNotes(c: c, sprint: sprint, closing: closing),
);

class _SprintNotes extends StatefulWidget {
  const _SprintNotes({
    required this.c,
    required this.sprint,
    required this.closing,
  });
  final ScrumController c;
  final ScrumSprint sprint;
  final bool closing;
  @override
  State<_SprintNotes> createState() => _SprintNotesState();
}

class _SprintNotesState extends State<_SprintNotes> {
  late final review = TextEditingController(text: widget.sprint.review);
  late final retro = TextEditingController(text: widget.sprint.retro);
  String? target;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    review.dispose();
    retro.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    final ok = await widget.c.write(
      widget.closing ? 'POST' : 'PATCH',
      '/sprints/${widget.sprint.id}/${widget.closing ? 'close' : 'notes'}',
      {'review': review.text, 'retro': retro.text, 'sprint_id': target},
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.c.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.closing ? 'پایان اسپرینت' : 'مرور و رترو'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.sprint.name),
            const SizedBox(height: 12),
            if (widget.closing) ...[
              const Text(
                'گزارش این نوبت ثبت می‌شود. کارهای ناتمام حذف نمی‌شوند؛ مقصدشان را انتخاب کن.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'انتقال کارهای ناتمام',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('بک‌لاگ')),
                  for (final s in widget.c.data!.sprints.where(
                    (s) => s.state == 'planned',
                  ))
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: saving ? null : (v) => target = v == '' ? null : v,
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: review,
              enabled: !saving,
              minLines: 2,
              maxLines: 5,
              maxLength: 20000,
              decoration: const InputDecoration(
                labelText: 'مرور · چه خروجی‌ای داشتیم؟',
                helperText: 'اختیاری',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: retro,
              enabled: !saving,
              minLines: 3,
              maxLines: 6,
              maxLength: 20000,
              decoration: const InputDecoration(
                labelText: 'رترو · دفعهٔ بعد چه تغییری بدهیم؟',
                helperText: 'اختیاری؛ برای خودت هم قابل استفاده است.',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(
          saving
              ? 'در حال ذخیره…'
              : widget.closing
              ? 'ثبت و پایان'
              : 'ذخیره',
        ),
      ),
    ],
  );
}
