import 'package:flutter/material.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/features/tasks/application/quick_capture.dart';
import 'package:menval/features/tasks/data/quick_parse.dart';
import 'package:menval/features/tasks/data/task.dart';

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
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 420 ? width : 420.0;

    return PopScope(
      canPop: !_busy,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          color: colors.surface,
          elevation: 12,
          shadowColor: colors.shadow.withValues(alpha: 0.16),
          borderRadius: const BorderRadiusDirectional.only(
            topEnd: Radius.circular(18),
            bottomEnd: Radius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: panelWidth,
            height: MediaQuery.sizeOf(context).height,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'کار جدید',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: 'بستن',
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _text,
                              autofocus: true,
                              enabled:
                                  !_busy && !widget.session.hasPendingRecurrence,
                              maxLength: 500,
                              buildCounter:
                                  (
                                    _, {
                                    required currentLength,
                                    required isFocused,
                                    maxLength,
                                  }) => null,
                              decoration: InputDecoration(
                                hintText: 'عنوان کار',
                                filled: true,
                                fillColor: colors.surfaceContainerLowest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              onChanged: (_) => setState(() {
                                _ignore.clear();
                                _error = null;
                              }),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.projectName,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
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
                                        _busy ||
                                            widget.session.hasPendingRecurrence
                                        ? null
                                        : () => setState(
                                            () => _ignore.add(
                                              (token.start, token.end),
                                            ),
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
                    const SizedBox(height: 16),
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
          ),
        ),
      ),
    );
  }
}
