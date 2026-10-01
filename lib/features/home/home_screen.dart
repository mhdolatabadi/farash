import 'package:flutter/material.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/archived_projects_screen.dart';
import 'package:farash/features/projects/presentation/project_sidebar.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/presentation/project_tasks_view.dart';

/// Wide layouts keep the project list on screen; phones use a drawer.
const sidebarBreakpoint = 840.0;

/// The signed-in shell: project navigation and the selected project.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.projects,
    required this.tasksApi,
    required this.token,
    this.sectionsApi,
  });

  final String email;
  final VoidCallback onLogout;
  final ProjectsController projects;
  final TasksApi tasksApi;
  final SectionsApi? sectionsApi;

  /// The current access token; null once signed out.
  final String? Function() token;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    widget.projects.load();
  }

  /// The selected project, falling back to the Inbox when it disappears.
  Project? get _selected =>
      widget.projects.byId(_selectedId) ?? widget.projects.inbox;

  void _select(Project project) {
    setState(() => _selectedId = project.id);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _openArchived() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ArchivedProjectsScreen(controller: widget.projects),
      ),
    );
  }

  Widget _sidebar() => ProjectSidebar(
    controller: widget.projects,
    selectedId: _selected?.id,
    onSelect: _select,
    onOpenArchived: _openArchived,
    header: _AccountHeader(email: widget.email, onLogout: widget.onLogout),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= sidebarBreakpoint;
        return ListenableBuilder(
          listenable: widget.projects,
          builder: (context, _) {
            final selected = _selected;
            final page = selected == null
                ? _ProjectPage(loading: widget.projects.isLoading)
                : ProjectTasksView(
                    // A new controller for each project.
                    key: ValueKey(selected.id),
                    project: selected,
                    api: widget.tasksApi,
                    sectionsApi: widget.sectionsApi,
                    token: widget.token,
                    moveTargets: () => widget.projects.projects,
                  );
            if (!wide) {
              return Scaffold(
                key: _scaffoldKey,
                appBar: AppBar(
                  title: Text(selected?.displayName ?? 'فراش'),
                  flexibleSpace: const GlassSurface(
                    radius: 0,
                    child: SizedBox.expand(),
                  ),
                ),
                drawer: Drawer(child: _sidebar()),
                body: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: GlassSurface(radius: 20, child: page),
                ),
              );
            }
            return Scaffold(
              key: _scaffoldKey,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: GlassSurface(child: _sidebar()),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GlassSurface(
                          child: Column(
                            children: [
                              AppBar(
                                automaticallyImplyLeading: false,
                                title: Text(selected?.displayName ?? 'فراش'),
                              ),
                              Expanded(child: page),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.email, required this.onLogout});

  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            'فراش',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
          title: Text(
            email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
          ),
          trailing: IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          ),
        ),
      ],
    );
  }
}

/// Shown until the projects (and so the Inbox) have loaded.
class _ProjectPage extends StatelessWidget {
  const _ProjectPage({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Text(
        'پروژه‌ها بارگذاری نشدند.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
