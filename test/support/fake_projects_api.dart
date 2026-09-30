import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';

/// Projects in memory, behaving like the API: the list includes archived
/// projects, the Inbox is protected and deleting a parent moves its
/// sub-projects to the top level.
class FakeProjectsApi implements ProjectsApi {
  FakeProjectsApi({List<Project>? projects})
    : _projects =
          projects ??
          [
            const Project(
              id: 'inbox',
              name: 'صندوق ورودی',
              color: '#2563eb',
              isInbox: true,
            ),
          ];

  final List<Project> _projects;
  int _nextId = 1;

  /// Thrown by the next call instead of answering.
  Object? failNext;

  /// Every update the app sent, in order.
  final updates = <(String, ProjectDraft)>[];

  List<Project> get all => List.unmodifiable(_projects);

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<List<Project>> listProjects(String token) async {
    _maybeFail();
    return List.of(_projects);
  }

  @override
  Future<Project> createProject(String token, ProjectDraft draft) async {
    _maybeFail();
    final project = Project(
      id: 'p${_nextId++}',
      name: draft.name!.trim(),
      color: draft.color ?? ProjectColor.defaultHex,
      parentId: draft.parentId,
      isFavorite: draft.isFavorite ?? false,
      sortOrder: draft.sortOrder ?? 0,
      kind: draft.kind ?? ProjectKind.project,
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
    updates.add((id, changes));
    final index = _projects.indexWhere((p) => p.id == id);
    if (index < 0) {
      throw const ApiException(
        'not found',
        statusCode: 404,
        code: 'project_not_found',
      );
    }
    final current = _projects[index];
    if (current.isInbox &&
        (changes.name != null ||
            changes.moveParent ||
            changes.isArchived != null)) {
      throw const ApiException('inbox', statusCode: 409, code: 'inbox_project');
    }
    final updated = Project(
      id: current.id,
      parentId: changes.moveParent ? changes.parentId : current.parentId,
      name: changes.name ?? current.name,
      color: changes.color ?? current.color,
      isInbox: current.isInbox,
      isFavorite: changes.isFavorite ?? current.isFavorite,
      isArchived: changes.isArchived ?? current.isArchived,
      sortOrder: changes.sortOrder ?? current.sortOrder,
      kind: current.kind,
    );
    _projects[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteProject(String token, String id) async {
    _maybeFail();
    _projects.removeWhere((p) => p.id == id);
    for (var i = 0; i < _projects.length; i++) {
      final p = _projects[i];
      if (p.parentId == id) {
        _projects[i] = Project(
          id: p.id,
          name: p.name,
          color: p.color,
          isFavorite: p.isFavorite,
          isArchived: p.isArchived,
          sortOrder: p.sortOrder,
          kind: p.kind,
        );
      }
    }
  }
}
