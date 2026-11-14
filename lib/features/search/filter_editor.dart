import 'package:flutter/material.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/search/search.dart';

/// The color a saved filter is drawn in, from its `#rrggbb`.
Color filterSwatch(String hex) => Color(
  0xFF000000 | (int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x8B88A0),
);

/// Creates a filter, or edits [filter]: its query (typed, or built from a
/// form), name, color, favourite, sort and grouping. Returns the saved
/// filter, or null when cancelled.
Future<SavedFilter?> showFilterEditor(
  BuildContext context, {
  required FiltersController controller,
  SavedFilter? filter,
  String initialQuery = '',
  String initialSort = 'due',
  String initialGroup = 'none',
  List<String> projectNames = const [],
  List<String> labelNames = const [],
}) => showDialog<SavedFilter>(
  context: context,
  builder: (context) => _FilterEditor(
    controller: controller,
    filter: filter,
    initialQuery: initialQuery,
    initialSort: initialSort,
    initialGroup: initialGroup,
    projectNames: projectNames,
    labelNames: labelNames,
  ),
);

class _FilterEditor extends StatefulWidget {
  const _FilterEditor({
    required this.controller,
    required this.filter,
    required this.initialQuery,
    required this.initialSort,
    required this.initialGroup,
    required this.projectNames,
    required this.labelNames,
  });

  final FiltersController controller;
  final SavedFilter? filter;
  final String initialQuery, initialSort, initialGroup;
  final List<String> projectNames, labelNames;

  @override
  State<_FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<_FilterEditor> {
  late final _name = TextEditingController(text: widget.filter?.name ?? '');
  late final _query = TextEditingController(
    text: widget.filter?.query ?? widget.initialQuery,
  );
  late String _color = widget.filter?.color ?? _colors.first;
  late bool _favorite = widget.filter?.favorite ?? true;
  late String _sort = widget.filter?.sort ?? widget.initialSort;
  late String _group = widget.filter?.groupBy ?? widget.initialGroup;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  // The form starts closed when a query is already written by hand.
  late bool _useForm = _query.text.trim().isEmpty;
  final _dates = <String>{};
  final _priorities = <int>{};
  final _projects = <String>[];
  final _labels = <String>[];
  final _text = TextEditingController();

  static final _colors = [
    for (final c in ProjectColor.all.take(12)) c.hex.toUpperCase(),
  ];

  static String _colorName(String hex) =>
      'رنگ ${ProjectColor.all.firstWhere((c) => c.hex.toUpperCase() == hex, orElse: () => ProjectColor(hex, hex)).label}';

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    _text.dispose();
    super.dispose();
  }

  void _rebuildQuery() {
    _query.text = SmartListForm(
      dates: _dates,
      priorities: _priorities,
      projects: _projects,
      labels: _labels,
      text: _text.text,
    ).toQuery();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.controller.save(
        SavedFilter(
          id: widget.filter?.id ?? '',
          name: _name.text.trim(),
          query: _query.text.trim(),
          sort: _sort,
          groupBy: _group,
          favorite: _favorite,
          color: _color,
        ),
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiException && error.statusCode == 400
            ? 'عبارت فیلتر معتبر نیست.'
            : 'فیلتر ذخیره نشد؛ دوباره تلاش کنید.';
      });
    }
  }

  Widget _chips<T>(
    String title,
    Iterable<(T, String)> choices,
    bool Function(T) selected,
    void Function(T, bool) onSelected,
  ) => Padding(
    padding: const EdgeInsets.only(top: Space.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: Space.xs),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final (value, label) in choices)
              FilterChip(
                label: Text(label),
                selected: selected(value),
                onSelected: (on) => setState(() {
                  onSelected(value, on);
                  _rebuildQuery();
                }),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _dropdown(
    String label,
    String value,
    List<(String, String)> choices,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final (v, text) in choices)
        DropdownMenuItem(value: v, child: Text(text)),
    ],
    onChanged: (v) {
      if (v != null) setState(() => onChanged(v));
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.filter == null ? 'فیلتر تازه' : 'ویرایش فیلتر'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: 'نام فیلتر',
                    errorText: _error,
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'نام فیلتر را بنویسید.' : null,
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.tune),
                      label: Text('با فرم'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.code),
                      label: Text('با عبارت'),
                    ),
                  ],
                  selected: {_useForm},
                  onSelectionChanged: (s) => setState(() => _useForm = s.first),
                ),
                if (_useForm) ...[
                  _chips<String>(
                    'تاریخ',
                    SmartListForm.dateChoices,
                    _dates.contains,
                    (v, on) => on ? _dates.add(v) : _dates.remove(v),
                  ),
                  _chips<int>(
                    'اولویت',
                    [for (var p = 1; p <= 4; p++) (p, 'اولویت $p')],
                    _priorities.contains,
                    (v, on) => on ? _priorities.add(v) : _priorities.remove(v),
                  ),
                  if (widget.projectNames.isNotEmpty)
                    _chips<String>(
                      'پروژه',
                      [for (final n in widget.projectNames) (n, n)],
                      _projects.contains,
                      (v, on) => on ? _projects.add(v) : _projects.remove(v),
                    ),
                  if (widget.labelNames.isNotEmpty)
                    _chips<String>(
                      'برچسب',
                      [for (final n in widget.labelNames) (n, '@$n')],
                      _labels.contains,
                      (v, on) => on ? _labels.add(v) : _labels.remove(v),
                    ),
                  const SizedBox(height: Space.sm),
                  TextField(
                    controller: _text,
                    decoration: const InputDecoration(
                      labelText: 'متن در عنوان، توضیح یا نظر',
                    ),
                    onChanged: (_) => setState(_rebuildQuery),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    _query.text.isEmpty ? 'همهٔ کارها' : _query.text,
                    key: const ValueKey('filter-query-preview'),
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: TextFormField(
                      controller: _query,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'عبارت فیلتر',
                        hintText: 'مثلاً امروز & p1',
                      ),
                    ),
                  ),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    Expanded(
                      child: _dropdown(
                        'مرتب‌سازی',
                        _sort,
                        filterSorts,
                        (v) => _sort = v,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _dropdown(
                        'گروه‌بندی',
                        _group,
                        filterGroups,
                        (v) => _group = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
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
                                    color: filterSwatch(hex),
                                    border: _color == hex
                                        ? Border.all(
                                            color: theme.colorScheme.onSurface,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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
