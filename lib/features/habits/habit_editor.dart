import 'package:flutter/material.dart';
import 'package:farash/core/calendar/date_labels.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/habits/habits_view.dart' show parseAmount;

/// Loop's add flow: choose yes/no or measurable, then fill in the habit.
Future<Habit?> createHabit(
  BuildContext context,
  HabitsController controller,
) async {
  final kind = await showDialog<HabitKind>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('نوع عادت'),
      children: [
        _KindOption(
          kind: HabitKind.boolean,
          title: 'بله یا نه',
          example: 'مثلاً: امروز ورزش کردی؟ امروز کتاب خواندی؟',
        ),
        _KindOption(
          kind: HabitKind.numeric,
          title: 'قابل اندازه‌گیری',
          example: 'مثلاً: چند لیوان آب خوردی؟ چند صفحه خواندی؟',
        ),
      ],
    ),
  );
  if (kind == null || !context.mounted) return null;
  return Navigator.of(context).push<Habit>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => HabitEditor(controller: controller, kind: kind),
    ),
  );
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.kind,
    required this.title,
    required this.example,
  });

  final HabitKind kind;
  final String title, example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(context, kind),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            example,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loop's frequency choices for a yes/no habit, then «سفارشی».
const _presets = [(1, 1), (1, 7), (2, 7), (5, 7)];

/// Creates a habit of [kind], or edits [habit].
class HabitEditor extends StatefulWidget {
  const HabitEditor({
    super.key,
    required this.controller,
    this.habit,
    this.kind = HabitKind.boolean,
  });

  final HabitsController controller;
  final Habit? habit;
  final HabitKind kind;

  @override
  State<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<HabitEditor> {
  late final Habit? _old = widget.habit;
  late final HabitKind _kind = _old?.kind ?? widget.kind;
  late final _name = TextEditingController(text: _old?.name);
  late final _question = TextEditingController(text: _old?.question);
  late final _notes = TextEditingController(text: _old?.notes);
  late final _unit = TextEditingController(text: _old?.unit);
  late final _target = TextEditingController(
    text: _old == null || _old.targetValue == 0
        ? ''
        : formatAmount(_old.targetValue),
  );
  late int _color = _old?.color ?? 8;
  late int _num = _old?.freqNum ?? 1;
  late int _den = _old?.freqDen ?? 1;
  late HabitTarget _bound = _old?.target ?? HabitTarget.atLeast;
  late int? _reminderMinute = _old?.reminderMinute;
  late int _reminderDays = _old?.reminderDays ?? Habit.everyDay;
  bool _notificationsBlocked = false;
  String? _nameError, _targetError;
  bool _saving = false;
  final _createAttempt = HabitCreateAttempt();

  bool get _numeric => _kind == HabitKind.numeric;

  @override
  void dispose() {
    for (final c in [_name, _question, _notes, _unit, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final target = _numeric ? parseAmount(_target.text) : 0.0;
    setState(() {
      _nameError = name.isEmpty ? 'نام عادت را بنویسید.' : null;
      _targetError =
          _numeric &&
              (target == null || (target == 0 && _bound == HabitTarget.atLeast))
          ? 'هدف را با یک عدد مثبت مشخص کنید.'
          : null;
    });
    if (_nameError != null || _targetError != null) return;
    final draft = HabitDraft(
      name: name,
      question: _question.text.trim(),
      notes: _notes.text.trim(),
      color: _color,
      kind: _old == null ? _kind : null,
      freqNum: _numeric ? 1 : _num,
      freqDen: _den,
      target: _numeric ? _bound : null,
      targetValue: _numeric ? target : null,
      unit: _numeric ? _unit.text.trim() : null,
      reminder: switch (_reminderMinute) {
        final minute? => HabitReminder(minute, days: _reminderDays),
        null when _old != null => HabitReminder.off(days: _reminderDays),
        null => null,
      },
    );
    setState(() => _saving = true);
    final old = _old;
    final Habit? saved;
    if (old == null) {
      saved = await widget.controller.create(draft, attempt: _createAttempt);
    } else {
      saved = await widget.controller.update(old, draft)
          ? widget.controller.byId(old.id)
          : null;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.pop(context, saved);
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رنگ'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 20; i++)
                Semantics(
                  button: true,
                  selected: i == _color,
                  label: persianDigits('رنگ ${i + 1}'),
                  child: InkResponse(
                    onTap: () => Navigator.pop(context, i),
                    radius: 26,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: habitColor(context, i),
                        shape: BoxShape.circle,
                      ),
                      child: i == _color
                          ? Icon(
                              Icons.check_rounded,
                              color:
                                  ThemeData.estimateBrightnessForColor(
                                        habitColor(context, i),
                                      ) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _color = picked);
  }

  Future<void> _customFrequency() async {
    final times = TextEditingController(text: persianDigits(_num));
    final days = TextEditingController(text: persianDigits(_den));
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialog) => AlertDialog(
            title: const Text('تکرار سفارشی'),
            content: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: times,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('بار در'),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: days,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(errorText: error),
                  ),
                ),
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 12),
                  child: Text('روز'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final n = parseAmount(times.text)?.toInt() ?? 0;
                  final d = parseAmount(days.text)?.toInt() ?? 0;
                  if (n < 1 || d < 1 || d > 365 || n > d) {
                    setDialog(() => error = 'نادرست');
                    return;
                  }
                  Navigator.pop(context, (n, d));
                },
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
      },
    );
    times.dispose();
    days.dispose();
    if (result == null) return;
    setState(() {
      _num = result.$1;
      _den = result.$2;
    });
  }

  Future<void> _pickReminder() async {
    final current = _reminderMinute ?? 9 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: 'ساعت یادآور',
    );
    if (picked == null || !mounted) return;
    setState(() => _reminderMinute = picked.hour * 60 + picked.minute);
    // Asked from the tap, as browsers require; the reminder is saved anyway
    // and starts showing once notifications are allowed.
    final reminders = widget.controller.reminders;
    if (reminders == null) return;
    final allowed = await reminders.requestPermission();
    if (mounted) setState(() => _notificationsBlocked = !allowed);
  }

  void _toggleDay(int weekday) {
    final days = _reminderDays ^ (1 << (weekday - 1));
    // At least one day stays chosen; no days is the same as no reminder.
    if (days != 0) setState(() => _reminderDays = days);
  }

  String _label(int n, int d) =>
      Habit(id: '', name: '', freqNum: n, freqDen: d).frequencyLabel;

  @override
  Widget build(BuildContext context) {
    final color = habitColor(context, _color);
    final isPreset = _presets.contains((_num, _den));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'بستن',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_old == null ? 'عادت تازه' : 'ویرایش عادت'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('ذخیره'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _name,
                        autofocus: _old == null,
                        textInputAction: TextInputAction.next,
                        maxLength: 200,
                        decoration: InputDecoration(
                          labelText: 'نام',
                          hintText: _numeric ? 'مثلاً آب' : 'مثلاً ورزش',
                          errorText: _nameError,
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'رنگ',
                      child: InkResponse(
                        onTap: _pickColor,
                        radius: 28,
                        child: Container(
                          width: 48,
                          height: 48,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _question,
                  maxLength: 300,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'پرسش',
                    hintText: _numeric
                        ? 'مثلاً امروز چند لیوان آب خوردی؟'
                        : 'مثلاً امروز ورزش کردی؟',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                if (_numeric) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _target,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'هدف',
                            errorText: _targetError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _unit,
                          maxLength: 40,
                          decoration: const InputDecoration(
                            labelText: 'واحد',
                            hintText: 'مثلاً لیوان',
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: [1, 7, 30].contains(_den) ? _den : 1,
                    decoration: const InputDecoration(labelText: 'بازه'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('در روز')),
                      DropdownMenuItem(value: 7, child: Text('در هفته')),
                      DropdownMenuItem(value: 30, child: Text('در ماه')),
                    ],
                    onChanged: (d) => setState(() => _den = d ?? 1),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<HabitTarget>(
                    segments: const [
                      ButtonSegment(
                        value: HabitTarget.atLeast,
                        label: Text('دست‌کم'),
                      ),
                      ButtonSegment(
                        value: HabitTarget.atMost,
                        label: Text('حداکثر'),
                      ),
                    ],
                    selected: {_bound},
                    onSelectionChanged: (s) => setState(() => _bound = s.first),
                  ),
                ] else
                  DropdownButtonFormField<(int, int)?>(
                    initialValue: isPreset ? (_num, _den) : null,
                    decoration: const InputDecoration(labelText: 'تکرار'),
                    items: [
                      for (final (n, d) in _presets)
                        DropdownMenuItem(
                          value: (n, d),
                          child: Text(_label(n, d)),
                        ),
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          isPreset
                              ? 'سفارشی…'
                              : '${_label(_num, _den)} (سفارشی)',
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        _customFrequency();
                      } else {
                        setState(() {
                          _num = value.$1;
                          _den = value.$2;
                        });
                      }
                    },
                  ),
                const SizedBox(height: 16),
                _ReminderField(
                  minute: _reminderMinute,
                  days: _reminderDays,
                  blocked: _notificationsBlocked,
                  onPick: _pickReminder,
                  onClear: () => setState(() {
                    _reminderMinute = null;
                    _notificationsBlocked = false;
                  }),
                  onToggleDay: _toggleDay,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت',
                    counterText: '',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Loop's reminder: off, or a time on chosen weekdays.
class _ReminderField extends StatelessWidget {
  const _ReminderField({
    required this.minute,
    required this.days,
    required this.blocked,
    required this.onPick,
    required this.onClear,
    required this.onToggleDay,
  });

  final int? minute;
  final int days;
  final bool blocked;
  final VoidCallback onPick, onClear;
  final ValueChanged<int> onToggleDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final minute = this.minute;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: minute == null
              ? 'یادآور، خاموش'
              : 'یادآور، ساعت ${formatMinuteOfDay(minute)}',
          excludeSemantics: true,
          child: InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'یادآور',
                prefixIcon: Icon(
                  minute == null
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                ),
                suffixIcon: minute == null
                    ? null
                    : IconButton(
                        tooltip: 'خاموش کردن یادآور',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: onClear,
                      ),
                helperText: blocked
                    ? 'اعلان‌ها مجاز نیستند. آن‌ها را در تنظیمات دستگاه روشن کنید.'
                    : null,
                helperMaxLines: 2,
                helperStyle: blocked ? TextStyle(color: scheme.error) : null,
              ),
              child: Text(
                minute == null ? 'خاموش' : formatMinuteOfDay(minute),
                style: minute == null
                    ? theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyLarge,
              ),
            ),
          ),
        ),
        if (minute != null) ...[
          const SizedBox(height: 12),
          Text(
            'روزها',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final weekday in persianWeekOrder)
                Expanded(
                  child: _DayToggle(
                    weekday: weekday,
                    selected: days & (1 << (weekday - 1)) != 0,
                    onTap: () => onToggleDay(weekday),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A round weekday toggle, as in Android's alarm clock. The whole column
/// width is the touch target.
class _DayToggle extends StatelessWidget {
  const _DayToggle({
    required this.weekday,
    required this.selected,
    required this.onTap,
  });

  final int weekday;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = weekdayNames[weekday - 1];
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        button: true,
        selected: selected,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? scheme.primary : null,
                  border: selected ? null : Border.all(color: scheme.outline),
                ),
                child: Text(
                  weekdayInitials[weekday - 1],
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
