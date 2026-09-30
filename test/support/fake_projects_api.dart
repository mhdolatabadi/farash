import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';

/// Projects in memory, with the API's tree order and Inbox rules.
class FakeProjectsApi implements ProjectsApi {
  FakeProjectsApi({List<Project>? projects})
    : _projects =
          projects ??
          [
            const Project(
              id: 'inbox',
              name: 'Inbox',
              color: 'charcoal',
              isInbox: true,
            ),
          ];

  final List<Project> _projects;
  int _nextId = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  List<Project> get all => List.unmodifiable(_projects);

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<List<Project>> listProjects(
    String token, {
    bool archived = false,
  }) async {
    _maybeFail();
    final active = _projects.where((p) => p.isArchived == archived).toList();
    final ordered = <Project>[];
    void add(String? parentId) {
      final children = active.where((p) => p.parentId == parentId).toList()
        ..sort((a, b) {
          if (a.isInbox != b.isInbox) return a.isInbox ? -1 : 1;
          return a.childOrder.compareTo(b.childOrder);
        });
      for (final child in children) {
        ordered.add(child);
        add(child.id);
      }
    }

    add(null);
    // Archived children of active parents still show up.
    for (final p in active) {
      if (!ordered.contains(p)) ordered.add(p);
    }
    return ordered;
  }

  @override
  Future<Project> createProject(String token, ProjectDraft draft) async {
    _maybeFail();
    final siblings = _projects.where((p) => p.parentId == draft.parentId);
    final project = Project(
      id: 'p${_nextId++}',
      name: draft.name!,
      color: draft.color ?? 'charcoal',
      parentId: draft.parentId,
      isFavorite: draft.isFavorite ?? false,
      childOrder: siblings.length,
    );
    _projects.add(project);
    return project;
  }

  @override
  Future<Project> updateProject(
    String token,
    String id,
    ProjectDraft changes,
  ) async {
    _maybeFail();
    final index = _projects.indexWhere((p) => p.id == id);
    if (index < 0) {
      throw const ApiException('not found', statusCode: 404, code: 'not_found');
    }
    final current = _projects[index];
    if (current.isInbox &&
        (changes.name != null ||
            changes.moveParent ||
            changes.isArchived != null)) {
      throw const ApiException(
        'inbox',
        statusCode: 400,
        code: 'inbox_protected',
      );
    }
    final updated = Project(
      id: current.id,
      parentId: changes.moveParent ? changes.parentId : current.parentId,
      name: changes.name ?? current.name,
      color: changes.color ?? current.color,
      isInbox: current.isInbox,
      isFavorite: changes.isFavorite ?? current.isFavorite,
      isArchived: changes.isArchived ?? current.isArchived,
      childOrder: current.childOrder,
    );
    _projects[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteProject(String token, String id) async {
    _maybeFail();
    final removed = {id};
    var grew = true;
    while (grew) {
      final before = removed.length;
      removed.addAll(
        _projects.where((p) => removed.contains(p.parentId)).map((p) => p.id),
      );
      grew = removed.length != before;
    }
    _projects.removeWhere((p) => removed.contains(p.id));
  }

  @override
  Future<void> reorderProjects(String token, List<String> ids) async {
    _maybeFail();
    for (var i = 0; i < ids.length; i++) {
      final index = _projects.indexWhere((p) => p.id == ids[i]);
      final p = _projects[index];
      _projects[index] = Project(
        id: p.id,
        parentId: p.parentId,
        name: p.name,
        color: p.color,
        isInbox: p.isInbox,
        isFavorite: p.isFavorite,
        isArchived: p.isArchived,
        childOrder: i,
      );
    }
  }
}
