import 'package:farash/features/tasks/data/task.dart';

abstract interface class SearchApi {
  Future<Map<String, dynamic>> searchRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

class SavedFilter {
  const SavedFilter({
    required this.id,
    required this.name,
    required this.query,
    required this.sort,
    required this.favorite,
    required this.color,
  });
  factory SavedFilter.fromJson(Map<String, dynamic> json) => SavedFilter(
    id: json['id'] as String,
    name: json['name'] as String,
    query: json['query'] as String,
    sort: json['sort'] as String,
    favorite: json['is_favorite'] as bool,
    color: json['color'] as String,
  );
  final String id, name, query, sort, color;
  final bool favorite;
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
