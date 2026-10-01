import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'fake_tasks_api.dart';

/// Sections in memory, behaving like the API. When given [tasks], deleting a
/// section takes its tasks out of it, or deletes them with deleteTasks.
class FakeSectionsApi implements SectionsApi {
  FakeSectionsApi({this.tasks});

  final FakeTasksApi? tasks;
  final _sections = <Section>[];
  int _nextId = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  List<Section> get all => List.unmodifiable(_sections);

  Section byName(String name) => _sections.firstWhere((s) => s.name == name);

  Section seed(String projectId, String name, {bool collapsed = false}) {
    final section = Section(
      id: 's${_nextId++}',
      projectId: projectId,
      name: name,
      sortOrder: _sections.where((s) => s.projectId == projectId).length,
      isCollapsed: collapsed,
    );
    _sections.add(section);
    return section;
  }

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  int _index(String id) {
    final index = _sections.indexWhere((s) => s.id == id);
    if (index < 0) {
      throw const ApiException(
        'not found',
        statusCode: 404,
        code: 'section_not_found',
      );
    }
    return index;
  }

  @override
  Future<List<Section>> listSections(String token, String projectId) async {
    _maybeFail();
    return [
      for (final s in _sections)
        if (s.projectId == projectId) s,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<Section> createSection(
    String token,
    String projectId,
    String name,
  ) async {
    _maybeFail();
    return seed(projectId, name.trim());
  }

  @override
  Future<Section> updateSection(
    String token,
    String id, {
    String? name,
    bool? isCollapsed,
  }) async {
    _maybeFail();
    final index = _index(id);
    final updated = _sections[index].copyWith(
      name: name?.trim(),
      isCollapsed: isCollapsed,
    );
    _sections[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteSection(
    String token,
    String id, {
    bool deleteTasks = false,
  }) async {
    _maybeFail();
    _sections.removeAt(_index(id));
    tasks?.removeSection(id, deleteTasks: deleteTasks);
  }

  @override
  Future<void> reorderSections(
    String token,
    String projectId,
    List<String> ids,
  ) async {
    _maybeFail();
    for (var i = 0; i < ids.length; i++) {
      final index = _index(ids[i]);
      _sections[index] = _sections[index].copyWith(sortOrder: i);
    }
  }
}
