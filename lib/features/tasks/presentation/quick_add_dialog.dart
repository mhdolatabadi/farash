import 'package:flutter/material.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/features/tasks/application/quick_capture.dart';
import 'package:menval/features/tasks/data/quick_parse.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/due_picker.dart';

/// The advanced capture surface, presented as a bottom sheet by the shell.
class QuickAddDialog extends StatefulWidget {
  const QuickAddDialog({
    super.key,
    required this.session,
    required this.projectName,
    this.initialText = '',
  });

  final QuickCaptureSession session;
  final String projectName;
  final String initialText;

  @override
  State<QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<QuickAddDialog> {
  late final TextEditingController _text;
  final _ignore = <(int, int)>{};
  TaskDue? _scheduledDue;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _chooseDateTime() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final chosen = await showDuePicker(
      context,
      initial: TaskDates(due: _scheduledDue),
      dueOnly: true,
    );
    if (mounted && chosen != null) {
      setState(() => _scheduledDue = chosen.due);
    }
  }

  Future<void> _submit() async {
    if (_busy || _text.text.trim().isEmpty) return;
    final raw = _text.text.trim();
    final parsed = parseQuickTask(raw, now: DateTime.now(), ignore: _ignore);
    final due = _scheduledDue;
    final capture = due == null
        ? parsed
        : QuickTask(
            title: parsed.title,
            day: due.day,
            hour: due.isTimed ? due.localTime!.hour : null,
            minute: due.isTimed ? due.localTime!.minute : 0,
            deadline: parsed.deadline,
            priority: parsed.priority,
            project: parsed.project,
            section: parsed.section,
            recurrence: parsed.recurrence,
            labels: parsed.labels,
            tokens: parsed.tokens,
          );
    final calendar = CalendarScope.of(context).isJalali
        ? 'jalali'
        : 'gregorian';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final task = await widget.session.capture(
        capture,
        raw,
        calendar: calendar,
      );
      if (mounted) Navigator.pop<Task>(context, task);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom -
        24;
    final height = availableHeight.clamp(160.0, 445.0).toDouble();
    final compact = availableHeight < 280;
    final parsed = parseQuickTask(
      _text.text,
      now: DateTime.now(),
      ignore: _ignore,
    );
    return PopScope(
      canPop: !_busy,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, compact ? 8 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              SizedBox(height: compact ? 4 : 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'کار جدید',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 14),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('quick-add-title'),
                        controller: _text,
                        autofocus: true,
                        enabled: !_busy && !widget.session.hasPendingRecurrence,
                        maxLength: 500,
                        buildCounter:
                            (
                              _, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        decoration: const InputDecoration(
                          hintText: 'عنوان کار',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        onChanged: (_) => setState(() {
                          _ignore.clear();
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 12),
                      Material(
                        color: colors.surface,
                        elevation: 1,
                        shadowColor: colors.shadow.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _busy ? null : _chooseDateTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule_outlined, size: 20),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _scheduledDue == null
                                        ? 'تاریخ و ساعت (اختیاری)'
                                        : describeDates(
                                            TaskDates(due: _scheduledDue),
                                            CalendarScope.of(context),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.projectName,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (parsed.tokens.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final token in parsed.tokens)
                              InputChip(
                                label: Text(token.text),
                                deleteButtonTooltipMessage:
                                    'نادیده گرفتن «${token.text}»',
                                onDeleted:
                                    _busy || widget.session.hasPendingRecurrence
                                    ? null
                                    : () => setState(
                                        () => _ignore.add((
                                          token.start,
                                          token.end,
                                        )),
                                      ),
                              ),
                          ],
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      ],
                      if (_busy)
                        const LinearProgressIndicator(
                          semanticsLabel: 'در حال ذخیرهٔ کار',
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Text(
                    widget.session.hasPendingRecurrence
                        ? 'ذخیرهٔ تکرار'
                        : 'افزودن کار',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
