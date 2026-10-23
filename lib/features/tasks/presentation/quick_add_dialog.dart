import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/features/tasks/application/quick_capture.dart';
import 'package:farash/features/tasks/data/quick_parse.dart';
import 'package:farash/features/tasks/data/task.dart';

class QuickAddDialog extends StatefulWidget {
  const QuickAddDialog({
    super.key,
    required this.session,
    required this.projectName,
  });
  final QuickCaptureSession session;
  final String projectName;
  @override
  State<QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<QuickAddDialog> {
  final _text = TextEditingController();
  final _ignore = <(int, int)>{};
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _text.text.trim().isEmpty) return;
    final raw = _text.text.trim();
    final parsed = parseQuickTask(raw, now: DateTime.now(), ignore: _ignore);
    final calendar = CalendarScope.of(context).isJalali
        ? 'jalali'
        : 'gregorian';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final task = await widget.session.capture(
        parsed,
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
    final parsed = parseQuickTask(
      _text.text,
      now: DateTime.now(),
      ignore: _ignore,
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('افزودن سریع کار'),
        scrollable: true,
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('پروژه: ${widget.projectName}'),
              const SizedBox(height: 12),
              TextField(
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
                  labelText: 'کار تازه',
                  hintText: 'مطالعه هر روز #کار /برنامه',
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                onChanged: (_) => setState(() {
                  _ignore.clear();
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final token in parsed.tokens)
                    InputChip(
                      label: Text(token.text),
                      deleteButtonTooltipMessage:
                          'نادیده گرفتن «${token.text}»',
                      onDeleted: _busy || widget.session.hasPendingRecurrence
                          ? null
                          : () => setState(
                              () => _ignore.add((token.start, token.end)),
                            ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              widget.session.hasPendingRecurrence
                  ? 'ذخیرهٔ تکرار'
                  : 'افزودن کار',
            ),
          ),
        ],
      ),
    );
  }
}
