import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/features/tasks/presentation/due_picker.dart';

import 'task_recurrence.dart';

const _frequencies = {
  'day': 'روز',
  'week': 'هفته',
  'month': 'ماه',
  'year': 'سال',
};
const _weekdays = [
  'یکشنبه',
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
];

class RecurrencePanel extends StatefulWidget {
  const RecurrencePanel({
    super.key,
    required this.task,
    required this.service,
    required this.datesSaved,
    required this.onRefresh,
    required this.onSkipped,
    this.disabled = false,
  });
  final Task task;
  final RecurrenceService service;
  final bool datesSaved, disabled;
  final Future<void> Function() onRefresh;
  final VoidCallback onSkipped;

  @override
  State<RecurrencePanel> createState() => _RecurrencePanelState();
}

class _RecurrencePanelState extends State<RecurrencePanel> {
  RecurrenceState? _state;
  bool _loading = true, _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.service.load(widget.task.id);
      if (mounted) setState(() => _state = state);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurrenceDialog(
        task: widget.task,
        service: widget.service,
        state: _state,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _skip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رد کردن این نوبت؟'),
        content: const Text(
          'نوبت بعد ساخته می‌شود؛ این نوبت امتیاز انجام نمی‌گیرد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('رد کردن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = widget.service;
    final taskId = widget.task.id;
    final refresh = widget.onRefresh;
    await _run(() async {
      await service.skip(taskId);
      await refresh();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('این نوبت رد شد.'),
          action: SnackBarAction(
            label: 'برگرداندن',
            onPressed: () async {
              try {
                await service.undo(taskId);
                await refresh();
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('بازگرداندن انجام نشد؛ فهرست را تازه کنید.'),
                  ),
                );
              }
            },
          ),
        ),
      );
      widget.onSkipped();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editable =
        !_loading &&
        !_busy &&
        !widget.disabled &&
        widget.datesSaved &&
        widget.task.due != null &&
        widget.task.parentId == null &&
        !widget.task.hasSubtasks &&
        !widget.task.isCompleted &&
        _state?.advanced != true &&
        _error == null;
    final state = _state;
    final rule = state?.rule;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.repeat),
      title: const Text('تکرار کار'),
      subtitle: Text(
        _loading
            ? 'در حال دریافت…'
            : state == null
            ? 'بدون تکرار'
            : 'هر ${persianDigits(rule?['interval'] ?? 1)} ${_frequencies[rule?['frequency']] ?? ''}',
      ),
      children: [
        if (_error != null) ...[
          const Text('دریافت یا ذخیرهٔ تکرار انجام نشد؛ دوباره تلاش کنید.'),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('تلاش دوباره'),
          ),
        ],
        if (!widget.datesSaved || widget.task.due == null)
          const Text('ابتدا تاریخ کار را تعیین و تغییرات را ذخیره کنید.'),
        if (widget.task.parentId != null || widget.task.hasSubtasks)
          const Text('تکرار فعلاً برای کار مستقل و بدون زیرکار در دسترس است.'),
        if (state != null)
          Text(
            'نوبت ${persianDigits(state.emitted)}؛ ${state.schedule['timezone']}',
          ),
        const Text(
          'تنظیم تکرار جداگانه ذخیره می‌شود. هر نوبت تاریخچهٔ مستقل دارد.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: editable ? _edit : null,
              child: Text(state == null ? 'تنظیم تکرار' : 'ویرایش تکرار'),
            ),
            if (state != null && !state.advanced) ...[
              TextButton(
                onPressed: editable
                    ? () => _run(() async {
                        final saved = await widget.service.save(
                          widget.task.id,
                          null,
                        );
                        if (mounted) setState(() => _state = saved);
                      })
                    : null,
                child: const Text('حذف تکرار'),
              ),
              TextButton(
                onPressed: editable ? _skip : null,
                child: const Text('رد کردن این نوبت'),
              ),
            ],
            if (state?.advanced == true && widget.task.isCompleted)
              TextButton(
                onPressed: _busy || widget.disabled
                    ? null
                    : () => _run(() async {
                        await widget.service.undo(widget.task.id);
                        await widget.onRefresh();
                        await _load();
                      }),
                child: const Text('بازگرداندن این نوبت'),
              ),
          ],
        ),
      ],
    );
  }
}

class _RecurrenceDialog extends StatefulWidget {
  const _RecurrenceDialog({
    required this.task,
    required this.service,
    this.state,
  });
  final Task task;
  final RecurrenceService service;
  final RecurrenceState? state;
  @override
  State<_RecurrenceDialog> createState() => _RecurrenceDialogState();
}

class _RecurrenceDialogState extends State<_RecurrenceDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _rule = widget.state?.rule ?? {};
  late String _frequency = _rule['frequency'] as String? ?? 'day';
  late String _basis = _rule['basis'] as String? ?? 'due';
  late String _calendar;
  late final _interval = TextEditingController(
    text: persianDigits(_rule['interval'] ?? 1),
  );
  late final _count = TextEditingController(
    text: _rule['count'] == null ? '' : persianDigits(_rule['count']!),
  );
  late String? _until = _rule['until'] as String?;
  late final Set<int> _selectedDays = {
    for (final day in _rule['weekdays'] as List? ?? []) day as int,
  };
  late int _monthDay = _rule['month_day'] as int? ?? 0;
  late int? _lastWeekday = _rule['last_weekday'] as int?;
  bool _busy = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calendar =
        widget.state?.rule['calendar'] as String? ??
        (CalendarScope.of(context).isJalali ? 'jalali' : 'gregorian');
  }

  @override
  void dispose() {
    _interval.dispose();
    _count.dispose();
    super.dispose();
  }

  int? _number(String text) => int.tryParse(
    text.trim().replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      const persian = '۰۱۲۳۴۵۶۷۸۹';
      const arabic = '٠١٢٣٤٥٦٧٨٩';
      final p = persian.indexOf(m[0]!);
      return '${p >= 0 ? p : arabic.indexOf(m[0]!)}';
    }),
  );

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final due = widget.task.due!;
      // A new timed rule uses the stored wall time only when the due's zone
      // matches this device. Existing schedules preserve their original wall time.
      final deviceZone = await deviceTimeZone();
      final zone =
          widget.state?.schedule['timezone'] as String? ??
          due.timezone ??
          deviceZone;
      String? wall = widget.state?.schedule['time'] as String?;
      if (due.isTimed && wall == null) {
        if (zone != deviceZone) throw StateError('zone');
        final local = due.localTime!;
        wall =
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      }
      final schedule = <String, Object?>{
        'start': widget.state?.schedule['start'] ?? due.date,
        'timezone': zone,
        'time': ?wall,
        'rule': {
          'frequency': _frequency,
          'interval': _number(_interval.text),
          'calendar': _calendar,
          'basis': _basis,
          if (_frequency == 'week' && _selectedDays.isNotEmpty)
            'weekdays': _selectedDays.toList()..sort(),
          if (_frequency == 'month' && _monthDay != 0) 'month_day': _monthDay,
          if (_frequency == 'month' && _lastWeekday != null)
            'last_weekday': _lastWeekday,
          if (_until != null) 'until': _until,
          if (_count.text.trim().isNotEmpty) 'count': _number(_count.text),
        },
      };
      await widget.service.save(widget.task.id, schedule);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'ذخیره نشد. تاریخ آغاز باید با روزهای انتخاب‌شده سازگار باشد؛ برای زمان‌دارها منطقهٔ زمانی دستگاه باید با کار یکسان باشد.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('تکرار کار'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'هر چند وقت'),
                items: [
                  for (final item in _frequencies.entries)
                    DropdownMenuItem(value: item.key, child: Text(item.value)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _frequency = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interval,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'فاصلهٔ تکرار'),
                validator: (v) =>
                    (_number(v ?? '') ?? 0) < 1 ||
                        (_number(v ?? '') ?? 0) > 1000
                    ? 'عددی بین ۱ تا ۱۰۰۰ بنویسید.'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _calendar,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'تقویم محاسبه'),
                items: const [
                  DropdownMenuItem(value: 'jalali', child: Text('هجری شمسی')),
                  DropdownMenuItem(value: 'gregorian', child: Text('میلادی')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _calendar = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _basis,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'مبنای نوبت بعد'),
                items: const [
                  DropdownMenuItem(
                    value: 'due',
                    child: Text('تاریخ برنامه‌ریزی‌شده'),
                  ),
                  DropdownMenuItem(
                    value: 'completion',
                    child: Text('زمان انجام'),
                  ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _basis = v!),
              ),
              if (_frequency == 'week')
                Wrap(
                  spacing: 6,
                  children: [
                    for (final i in [6, 0, 1, 2, 3, 4, 5])
                      FilterChip(
                        label: Text(_weekdays[i]),
                        selected: _selectedDays.contains(i),
                        onSelected: _busy
                            ? null
                            : (selected) => setState(() {
                                if (selected) {
                                  _selectedDays.add(i);
                                } else {
                                  _selectedDays.remove(i);
                                }
                              }),
                      ),
                  ],
                ),
              if (_frequency == 'month') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _lastWeekday == null ? _monthDay : -1,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'روز ماه'),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('همان روز آغاز'),
                    ),
                    for (var i = 1; i <= 31; i++)
                      DropdownMenuItem(value: i, child: Text(persianDigits(i))),
                    const DropdownMenuItem(
                      value: -1,
                      child: Text('آخرین روز هفته در ماه'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _monthDay = v! < 0 ? 0 : v;
                          _lastWeekday = v < 0 ? 5 : null;
                        }),
                ),
                if (_lastWeekday != null)
                  DropdownButtonFormField<int>(
                    initialValue: _lastWeekday,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'روز هفته'),
                    items: [
                      for (var i = 0; i < 7; i++)
                        DropdownMenuItem(value: i, child: Text(_weekdays[i])),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _lastWeekday = v),
                  ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _count,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'تعداد کل نوبت‌ها (اختیاری)',
                ),
                validator: (v) => (v ?? '').trim().isEmpty
                    ? null
                    : (_number(v!) ?? 0) < 1 || (_number(v) ?? 0) > 1000000
                    ? 'عددی بین ۱ تا ۱۰۰۰۰۰۰ بنویسید.'
                    : null,
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final picked = await showDuePicker(
                          context,
                          initial: TaskDates(
                            due: _until == null ? null : TaskDue(date: _until!),
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _until = picked.due?.date);
                        }
                      },
                child: Text(
                  _until == null
                      ? 'انتخاب تاریخ پایان (اختیاری)'
                      : 'پایان: ${persianDigits(_until!)}',
                ),
              ),
              if (_until != null)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _until = null),
                  child: const Text('حذف تاریخ پایان'),
                ),
              const Text(
                'نوبت‌های ازدست‌رفته روی هم انباشته نمی‌شوند. برای زیرکارها فعلاً تکرار فعال نمی‌شود.',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'در حال ذخیره…' : 'ذخیرهٔ تکرار'),
      ),
    ],
  );
}
