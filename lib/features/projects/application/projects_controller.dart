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

/// The signed-in account's projects.
class ProjectsController extends ChangeNotifier {
  ProjectsController({required ProjectsApi api, required this.token})
    : _api = api;

  final ProjectsApi _api;

  /// The current access token; null once signed out.
  final String? Function() token;

  List<Project> _all = const [];
  bool _loading = false;
  Object? _error;

  /// Active projects, in tree order with the Inbox first.
  List<Project> get projects => [?inbox, for (final node in tree) node.project];

  /// Archived projects, in the API's order.
  List<Project> get archivedProjects =>
      _all.where((p) => p.isArchived).toList();

  bool get isLoading => _loading;

  /// The last load failure, shown with a retry action.
  Object? get error => _error;

  Project? get inbox => _all.where((p) => p.isInbox).firstOrNull;

  List<Project> get favorites => [
    for (final node in tree)
      if (node.project.isFavorite) node.project,
  ];

  Project? byId(String? id) => id == null
      ? null
      : _all.where((p) => p.id == id && !p.isArchived).firstOrNull;

  /// Active projects except the Inbox, each after its parent, siblings by
  /// sort order. A project whose parent is gone or archived shows at the
  /// top level; a parent loop is cut where it closes.
  List<ProjectNode> get tree {
    final active = [
      for (final p in _all)
        if (!p.isInbox && !p.isArchived) p,
    ];
    final ids = {for (final p in active) p.id};
    String? parentOf(Project p) =>
        p.parentId != null && ids.contains(p.parentId) ? p.parentId : null;

    final children = <String?, List<Project>>{};
    for (final p in active) {
      children.putIfAbsent(parentOf(p), () => []).add(p);
    }
    for (final list in children.values) {
      // A stable sort keeps the API's order for equal sort orders.
      mergeSort(list, compare: (a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    final nodes = <ProjectNode>[];
    final visited = <String>{};
    void visit(String? parentId, int depth) {
      for (final p in children[parentId] ?? const <Project>[]) {
        if (!visited.add(p.id)) continue;
        nodes.add(
          ProjectNode(
            p,
            depth,
            hasChildren: children[p.id]?.isNotEmpty ?? false,
          ),
        );
        visit(p.id, depth + 1);
      }
    }

    visit(null, 0);
    return nodes;
  }

  /// The active sub-projects of [parentId] as shown in the tree, in order;
  /// null gives the top level.
  List<Project> childrenOf(String? parentId) => [
    for (final node in tree)
      if (parentId == null
          ? node.depth == 0
          : node.depth > 0 && node.project.parentId == parentId)
        node.project,
  ];

  /// [project] and the projects shown next to it, in order.
  List<Project> siblingsOf(Project project) {
    final node = tree.where((n) => n.project.id == project.id).firstOrNull;
    if (node == null) return const [];
    return childrenOf(node.depth == 0 ? null : project.parentId);
  }

  Future<void> load() async {
    final token = this.token();
    if (token == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _all = await _api.listProjects(token);
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
    ProjectKind kind = ProjectKind.project,
  }) async {
    final siblings = childrenOf(parentId);
    final project = await _api.createProject(
      _requireToken(),
      ProjectDraft(
        name: name,
        color: color,
        parentId: parentId,
        isFavorite: isFavorite,
        kind: kind,
        sortOrder: siblings.isEmpty ? 0 : siblings.last.sortOrder + 1,
      ),
    );
    await load();
    return project;
  }

  /// Saves an edit. The Inbox keeps its name and place.
  Future<void> edit(
    Project project, {
    required String name,
    required String color,
    required String? parentId,
    required bool isFavorite,
  }) async {
    final moved = !project.isInbox && parentId != project.parentId;
    await _api.updateProject(
      _requireToken(),
      project.id,
      ProjectDraft(
        name: project.isInbox ? null : name,
        color: color,
        isFavorite: isFavorite,
        parentId: moved ? parentId : null,
        moveParent: moved,
      ),
    );
    await load();
  }

  Future<void> setFavorite(Project project, bool favorite) async {
    final before = _all;
    _replace(project.copyWith(isFavorite: favorite));
    try {
      await _api.updateProject(
        _requireToken(),
        project.id,
        ProjectDraft(isFavorite: favorite),
      );
    } catch (_) {
      _all = before;
      notifyListeners();
      rethrow;
    }
  }

  /// Archives the project; it leaves the sidebar.
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

  /// Deletes the project; its sub-projects move to the top level.
  Future<void> delete(Project project) async {
    await _api.deleteProject(_requireToken(), project.id);
    await load();
  }

  /// Moves [project] to [newIndex] among its siblings and saves the new
  /// sort orders of the siblings that changed.
  Future<void> reorder(Project project, int newIndex) async {
    final siblings = siblingsOf(project);
    final oldIndex = siblings.indexWhere((p) => p.id == project.id);
    if (oldIndex < 0 || oldIndex == newIndex) return;
    siblings.removeAt(oldIndex);
    siblings.insert(newIndex.clamp(0, siblings.length), project);
    final token = _requireToken();
    for (var i = 0; i < siblings.length; i++) {
      if (siblings[i].sortOrder == i) continue;
      await _api.updateProject(
        token,
        siblings[i].id,
        ProjectDraft(sortOrder: i),
      );
    }
    await load();
  }

  /// Forgets the account's projects, for sign-out.
  void clear() {
    _all = const [];
    _error = null;
    notifyListeners();
  }

  void _replace(Project updated) {
    _all = [for (final p in _all) p.id == updated.id ? updated : p];
    notifyListeners();
  }

  String _requireToken() {
    final token = this.token();
    if (token == null) {
      throw const ApiException('نشست شما منقضی شده است. دوباره وارد شوید.');
    }
    return token;
  }
}
