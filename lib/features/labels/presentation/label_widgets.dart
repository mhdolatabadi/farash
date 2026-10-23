import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/presentation/task_messages.dart';

/// "@name" in the label's color, as task rows show it.
class LabelTag extends StatelessWidget {
  const LabelTag({super.key, required this.label});

  final Label label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'برچسب ${label.name}',
      excludeSemantics: true,
      child: Text(
        label.tag,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(color: label.swatch),
      ),
    );
  }
}

/// Creates a label, or edits [label]: its name, color and favourite.
/// Returns the saved label, or null when cancelled.
Future<Label?> showLabelEditor(
  BuildContext context, {
  required LabelsController controller,
  Label? label,
  String initialName = '',
}) => showDialog<Label>(
  context: context,
  builder: (context) => _LabelEditor(
    controller: controller,
    label: label,
    initialName: initialName,
  ),
);

class _LabelEditor extends StatefulWidget {
  const _LabelEditor({
    required this.controller,
    required this.label,
    required this.initialName,
  });

  final LabelsController controller;
  final Label? label;
  final String initialName;

  @override
  State<_LabelEditor> createState() => _LabelEditorState();
}

class _LabelEditorState extends State<_LabelEditor> {
  late final _name = TextEditingController(
    text: widget.label?.name ?? widget.initialName,
  );
  late String _color = widget.label?.color ?? Label.defaultColor;
  late bool _favorite = widget.label?.isFavorite ?? false;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  static final _colors = [
    Label.defaultColor,
    for (final c in ProjectColor.all.take(11)) c.hex.toUpperCase(),
  ];

  /// A spoken name for a swatch, from the project palette.
  static String _colorName(String hex) => hex == Label.defaultColor
      ? 'رنگ پیش‌فرض'
      : 'رنگ ${ProjectColor.all.firstWhere((c) => c.hex.toUpperCase() == hex, orElse: () => ProjectColor(hex, hex)).label}';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final draft = LabelDraft(
        name: _name.text.trim(),
        color: _color,
        isFavorite: _favorite,
      );
      final existing = widget.label;
      final Label saved;
      if (existing == null) {
        saved = await widget.controller.create(draft);
      } else {
        await widget.controller.update(existing, draft);
        saved = widget.controller.byId(existing.id) ?? existing;
      }
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (error) {
          ApiException(code: 'duplicate_label') => 'برچسبی با این نام دارید.',
          _ => taskErrorMessage(error),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label == null ? 'برچسب تازه' : 'ویرایش برچسب'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: 'نام',
                  prefixText: '@',
                  errorText: _error,
                ),
                validator: (value) {
                  final name = (value ?? '').trim().replaceFirst('@', '');
                  return name.isEmpty ? 'نام برچسب را بنویسید.' : null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final hex in _colors)
                    Semantics(
                      button: true,
                      selected: _color == hex,
                      label: _colorName(hex),
                      excludeSemantics: true,
                      child: Tooltip(
                        message: _colorName(hex),
                        child: InkResponse(
                          onTap: () => setState(() => _color = hex),
                          radius: 24,
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Label(
                                    id: '',
                                    name: '',
                                    color: hex,
                                  ).swatch,
                                  border: _color == hex
                                      ? Border.all(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          width: 3,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('علاقه‌مندی'),
                value: _favorite,
                onChanged: (v) => setState(() => _favorite = v),
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
          child: const Text('ذخیره'),
        ),
      ],
    );
  }
}

/// Asks before deleting a label; its tasks stay.
Future<bool> confirmLabelDelete(BuildContext context, Label label) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف ${label.tag}؟'),
        content: const Text(
          'برچسب از همهٔ کارها برداشته می‌شود؛ خود کارها می‌مانند.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    ) ??
    false;
