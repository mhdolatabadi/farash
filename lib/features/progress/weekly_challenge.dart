import 'package:flutter/material.dart';
import 'package:farash/core/text/persian_digits.dart';

class WeeklyChallenge extends StatelessWidget {
  const WeeklyChallenge({
    super.key,
    required this.completed,
    required this.target,
    required this.onSave,
  });
  final int completed;
  final int target;
  final Future<void> Function(int) onSave;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'چالش شخصی این هفته',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('${persianDigits(completed)} از ${persianDigits(target)} کار'),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (completed / target).clamp(0, 1),
            semanticsLabel: 'پیشرفت چالش هفتگی',
          ),
          const SizedBox(height: 8),
          Text(
            completed >= target
                ? 'به هدف این هفته رسیدید.'
                : '${persianDigits(target - completed)} کار تا هدف؛ با ریتم خودتان ادامه دهید.',
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ChallengeEditor(target: target, onSave: onSave),
            ),
            child: const Text('تغییر هدف چالش'),
          ),
        ],
      ),
    ),
  );
}

class _ChallengeEditor extends StatefulWidget {
  const _ChallengeEditor({required this.target, required this.onSave});
  final int target;
  final Future<void> Function(int) onSave;
  @override
  State<_ChallengeEditor> createState() => _ChallengeEditorState();
}

class _ChallengeEditorState extends State<_ChallengeEditor> {
  final _form = GlobalKey<FormState>();
  late final _text = TextEditingController(text: persianDigits(widget.target));
  bool _saving = false;
  String? _error;
  int? _parse(String value) {
    const digits = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
    return int.tryParse(
      value.trim().split('').map((c) {
        final i = digits.indexOf(c);
        return i < 0 ? c : '${i % 10}';
      }).join(),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_parse(_text.text)!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = 'هدف ذخیره نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('هدف چالش هفتگی'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _text,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'تعداد کار',
                  helperText: 'از ۱ تا ۵۰۰ کار در هفته',
                  helperMaxLines: 2,
                  errorMaxLines: 4,
                ),
                validator: (value) {
                  final target = _parse(value ?? '');
                  return target == null || target < 1 || target > 500
                      ? 'عددی بین ۱ و ۵۰۰ وارد کنید.'
                      : null;
                },
              ),
              const Text(
                'هدف جدید برای همین هفته اعمال می‌شود. غیبت جریمه ندارد و امتیاز اضافه‌ای داده نمی‌شود.',
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'در حال ذخیره…' : 'ذخیره'),
        ),
      ],
    ),
  );
}
