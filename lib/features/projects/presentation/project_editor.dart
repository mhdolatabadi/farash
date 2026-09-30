import 'package:flutter/material.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/project_messages.dart';

/// Opens the editor for a new project (optionally under [parent]) or for
/// [project]. Returns the created project, if any.
Future<void> showProjectEditor(
  BuildContext context, {
  required ProjectsController controller,
  Project? project,
  Project? parent,
  ValueChanged<Project>? onCreated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ProjectEditor(
      controller: controller,
      project: project,
      initialParentId: project?.parentId ?? parent?.id,
      onCreated: onCreated,
    ),
  );
}

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({
    required this.controller,
    required this.project,
    required this.initialParentId,
    required this.onCreated,
  });

  final ProjectsController controller;
  final Project? project;
  final String? initialParentId;
  final ValueChanged<Project>? onCreated;

  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late String _color = widget.project?.color ?? ProjectColor.defaultKey;
  late String? _parentId = widget.initialParentId;
  late bool _favorite = widget.project?.isFavorite ?? false;
  bool _saving = false;

  bool get _isInbox => widget.project?.isInbox ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Projects this one may move under: not itself, not its descendants.
  List<ProjectNode> get _parentChoices {
    final nodes = widget.controller.tree;
    final self = widget.project;
    if (self == null) return nodes;
    final excluded = <String>{self.id};
    for (final node in nodes) {
      if (excluded.contains(node.project.parentId)) {
        excluded.add(node.project.id);
      }
    }
    return [
      for (final node in nodes)
        if (!excluded.contains(node.project.id)) node,
    ];
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final project = widget.project;
      if (project == null) {
        final created = await widget.controller.create(
          name: _name.text.trim(),
          color: _color,
          parentId: _parentId,
          isFavorite: _favorite,
        );
        widget.onCreated?.call(created);
      } else {
        await widget.controller.edit(
          project,
          name: _name.text.trim(),
          color: _color,
          parentId: _parentId,
          isFavorite: _favorite,
        );
      }
      navigator.pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showProjectError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.project == null;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isNew ? 'پروژهٔ تازه' : 'ویرایش پروژه',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              if (_isInbox)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('صندوق ورودی'),
                  subtitle: const Text('نام و جای صندوق ورودی ثابت است.'),
                )
              else
                TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'نام'),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'نام پروژه را بنویسید.'
                      : null,
                ),
              const SizedBox(height: 12),
              Text('رنگ', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _ColorChooser(
                selected: _color,
                onChanged: (color) => setState(() => _color = color),
              ),
              if (!_isInbox) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  initialValue: _parentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'زیرمجموعهٔ'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('هیچ‌کدام (سطح اول)'),
                    ),
                    for (final node in _parentChoices)
                      DropdownMenuItem<String?>(
                        value: node.project.id,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: 16.0 * node.depth,
                          ),
                          child: Text(
                            node.project.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _parentId = value),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('در علاقه‌مندی‌ها'),
                value: _favorite,
                onChanged: (value) => setState(() => _favorite = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isNew ? 'افزودن پروژه' : 'ذخیره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorChooser extends StatelessWidget {
  const _ColorChooser({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.onSurface;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final color in ProjectColor.all)
          Semantics(
            selected: color.key == selected,
            button: true,
            label: color.label,
            child: Tooltip(
              message: color.label,
              child: InkResponse(
                onTap: () => onChanged(color.key),
                radius: 24,
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.key == selected
                              ? outline
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: color.key == selected
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
