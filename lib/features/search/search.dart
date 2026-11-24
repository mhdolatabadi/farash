import 'package:flutter/foundation.dart';
import 'package:menval/features/tasks/data/task.dart';

abstract interface class SearchApi {
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

/// How a filter's results are ordered.
const filterSorts = [
  ('due', 'موعد'),
  ('priority', 'اولویت'),
  ('title', 'عنوان'),
  ('project', 'پروژه'),
];

/// How a filter's results are split into groups.
const filterGroups = [
  ('none', 'بدون گروه'),
  ('date', 'تاریخ'),
  ('priority', 'اولویت'),
  ('project', 'پروژه'),
  ('label', 'برچسب'),
];

class SavedFilter {
  const SavedFilter({
    required this.id,
    required this.name,
    required this.query,
    required this.sort,
    required this.favorite,
    required this.color,
    this.groupBy = 'none',
  });
  factory SavedFilter.fromJson(Map<String, dynamic> json) => SavedFilter(
    id: json['id'] as String,
    name: json['name'] as String,
    query: json['query'] as String,
    sort: json['sort'] as String,
    favorite: json['is_favorite'] as bool,
    color: json['color'] as String,
    groupBy: json['group_by'] as String? ?? 'none',
  );
  final String id, name, query, sort, color, groupBy;
  final bool favorite;

  Map<String, Object?> toJson() => {
    'name': name,
    'query': query,
    'sort': sort,
    'group_by': groupBy,
    'is_favorite': favorite,
    'color': color,
  };
}

/// The account's saved filters, shared by the sidebar and the search page.
class FiltersController extends ChangeNotifier {
  FiltersController({required this.api, required this.token});

  final SearchApi api;
  final String? Function() token;

  List<SavedFilter> _filters = const [];
  Object? _error;

  /// Favourites first, then oldest first, as the API lists them.
  List<SavedFilter> get filters => _filters;
  Object? get error => _error;

  SavedFilter? byId(String? id) =>
      id == null ? null : _filters.where((f) => f.id == id).firstOrNull;

  String _token() {
    final current = token();
    if (current == null) throw StateError('signed out');
    return current;
  }

  Future<void> load() async {
    if (token() == null) return;
    try {
      final result = await api.searchRequest(
        _token(),
        'GET',
        '/api/v1/filters',
      );
      _filters = [
        for (final f in result['filters'] as List<dynamic>)
          SavedFilter.fromJson(f as Map<String, dynamic>),
      ];
      _error = null;
    } catch (error) {
      _error = error;
    }
    notifyListeners();
  }

  /// Creates [filter] when its id is empty, otherwise replaces it.
  Future<SavedFilter> save(SavedFilter filter) async {
    final result = await api.searchRequest(
      _token(),
      filter.id.isEmpty ? 'POST' : 'PUT',
      filter.id.isEmpty
          ? '/api/v1/filters'
          : '/api/v1/filters/${Uri.encodeComponent(filter.id)}',
      body: filter.toJson(),
    );
    final saved = SavedFilter.fromJson(
      result['filter'] as Map<String, dynamic>,
    );
    await load();
    return saved;
  }

  Future<void> delete(SavedFilter filter) async {
    await api.searchRequest(
      _token(),
      'DELETE',
      '/api/v1/filters/${Uri.encodeComponent(filter.id)}',
    );
    await load();
  }
}

/// A smart list made from a form: each part is optional, and every chosen
/// part must hold. Turns into the same query language the search box reads.
class SmartListForm {
  const SmartListForm({
    this.dates = const {},
    this.priorities = const {},
    this.projects = const [],
    this.labels = const [],
    this.text = '',
  });

  /// Any of: today, overdue, 7days, nodate.
  final Set<String> dates;
  final Set<int> priorities;

  /// Project and label names, as the user sees them.
  final List<String> projects, labels;
  final String text;

  static const dateChoices = [
    ('today', 'امروز'),
    ('overdue', 'دیرشده'),
    ('7days', '۷ روز آینده'),
    ('nodate', 'بی‌تاریخ'),
  ];

  static String _quote(String name) => name.contains(RegExp(r'[\s&|!()"]'))
      ? '"${name.replaceAll('"', '')}"'
      : name;

  static String _any(List<String> parts) =>
      parts.length == 1 ? parts.single : '(${parts.join(' | ')})';

  String toQuery() {
    final all = <String>[
      if (dates.isNotEmpty)
        _any([
          for (final (value, _) in dateChoices)
            if (dates.contains(value))
              switch (value) {
                '7days' => '7 days',
                'nodate' => 'no date',
                _ => value,
              },
        ]),
      if (priorities.isNotEmpty)
        _any([for (final p in priorities.toList()..sort()) 'p$p']),
      if (projects.isNotEmpty)
        _any([for (final p in projects) '#${_quote(p)}']),
      if (labels.isNotEmpty) _any([for (final l in labels) '@${_quote(l)}']),
      // Free text is always quoted, so «امروز» typed here is a word, not a date.
      if (text.replaceAll('"', '').trim().isNotEmpty)
        '"${text.replaceAll('"', '').trim()}"',
    ];
    return all.join(' & ');
  }
}

class SearchPage {
  const SearchPage(this.tasks, this.hasMore);
  factory SearchPage.fromJson(Map<String, dynamic> json) => SearchPage([
    for (final t in json['tasks'] as List<dynamic>)
      Task.fromJson(t as Map<String, dynamic>),
  ], json['has_more'] as bool);
  final List<Task> tasks;
  final bool hasMore;
}
