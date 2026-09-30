import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/projects/data/project.dart';

/// A project with its depth in the tree, for the sidebar.
class ProjectNode {
  const ProjectNode(this.project, this.depth, {this.hasChildren = false});

  final Project project;

  /// 0 for top-level projects.
  final int depth;
  final bool hasChildren;
}

/// The signed-in account's projects, in the API's tree order.
class ProjectsController extends ChangeNotifier {
  ProjectsController({required ProjectsApi api, required this.token})
    : _api = api;

  final ProjectsApi _api;

  /// The current access token; null once signed out.
  final String? Function() token;

  List<Project> _projects = const [];
  bool _loading = false;
  Object? _error;

  List<Project> get projects => _projects;
  bool get isLoading => _loading;

  /// The last load failure, shown with a retry action.
  Object? get error => _error;

  Project? get inbox => _projects.where((p) => p.isInbox).firstOrNull;

  List<Project> get favorites =>
      _projects.where((p) => p.isFavorite && !p.isInbox).toList();

  Project? byId(String? id) =>
      id == null ? null : _projects.where((p) => p.id == id).firstOrNull;

  /// Every project except the Inbox, each with its depth, in tree order.
  List<ProjectNode> get tree {
    final byId = {for (final p in _projects) p.id: p};
    final parents = {for (final p in _projects) ?p.parentId};
    int depthOf(Project p) {
      var depth = 0;
      var parent = byId[p.parentId];
      while (parent != null && depth < 8) {
        depth++;
        parent = byId[parent.parentId];
      }
      return depth;
    }

    return [
      for (final p in _projects)
        if (!p.isInbox)
          ProjectNode(p, depthOf(p), hasChildren: parents.contains(p.id)),
    ];
  }

  /// The project's own sub-projects, in order.
  List<Project> childrenOf(String? parentId) =>
      _projects.where((p) => !p.isInbox && p.parentId == parentId).toList();

  Future<void> load() async {
    final token = this.token();
    if (token == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _projects = await _api.listProjects(token);
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Project> create({
    required String name,
    required String color,
    String? parentId,
    bool isFavorite = false,
  }) async {
    final project = await _api.createProject(
      _requireToken(),
      ProjectDraft(
        name: name,
        color: color,
        parentId: parentId,
        isFavorite: isFavorite,
      ),
    );
    await load();
    return project;
  }

  /// Saves an edit. Moving under another parent reloads the tree.
  Future<void> edit(
    Project project, {
    required String name,
    required String color,
    required String? parentId,
    required bool isFavorite,
  }) async {
    final moved = parentId != project.parentId;
    await _api.updateProject(
      _requireToken(),
      project.id,
      ProjectDraft(
        name: project.isInbox ? null : name,
        color: color,
        isFavorite: isFavorite,
        parentId: parentId,
        moveParent: moved,
      ),
    );
    await load();
  }

  Future<void> setFavorite(Project project, bool favorite) => _optimistic(
    project.copyWith(isFavorite: favorite),
    ProjectDraft(isFavorite: favorite),
  );

  /// Archives the project and its sub-projects; they leave the sidebar.
  Future<void> archive(Project project) async {
    await _api.updateProject(
      _requireToken(),
      project.id,
      const ProjectDraft(isArchived: true),
    );
    await load();
  }

  Future<void> unarchive(Project project) async {
    await _api.updateProject(
      _requireToken(),
      project.id,
      const ProjectDraft(isArchived: false),
    );
    await load();
  }

  Future<List<Project>> archived() =>
      _api.listProjects(_requireToken(), archived: true);

  Future<void> delete(Project project) async {
    await _api.deleteProject(_requireToken(), project.id);
    await load();
  }

  /// Moves [project] to [newIndex] among its siblings.
  Future<void> reorder(Project project, int newIndex) async {
    final siblings = childrenOf(project.parentId);
    final oldIndex = siblings.indexWhere((p) => p.id == project.id);
    if (oldIndex < 0 || oldIndex == newIndex) return;
    siblings.removeAt(oldIndex);
    siblings.insert(newIndex.clamp(0, siblings.length), project);
    await _api.reorderProjects(_requireToken(), [
      for (final p in siblings) p.id,
    ]);
    await load();
  }

  /// Forgets the account's projects, for sign-out.
  void clear() {
    _projects = const [];
    _error = null;
    notifyListeners();
  }

  Future<void> _optimistic(Project updated, ProjectDraft changes) async {
    final before = _projects;
    _projects = [for (final p in _projects) p.id == updated.id ? updated : p];
    notifyListeners();
    try {
      await _api.updateProject(_requireToken(), updated.id, changes);
    } catch (_) {
      _projects = before;
      notifyListeners();
      rethrow;
    }
  }

  String _requireToken() {
    final token = this.token();
    if (token == null) {
      throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.');
    }
    return token;
  }
}
