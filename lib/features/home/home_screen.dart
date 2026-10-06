import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings_dialog.dart';
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

  /// The project the lamp was last placed for.
  String? _lampFor;

  /// Moves the lamp behind the glass when the project changes, after the
  /// frame so the backdrop never rebuilds mid-build.
  void _placeLamp(Project? project) {
    if (project == null || project.id == _lampFor) return;
    _lampFor = project.id;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => GlassLamp.placeFor(project.id),
    );
  }

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
            _placeLamp(selected);
            final Widget content = selected == null
                ? _ProjectPage(loading: widget.projects.isLoading)
                : ProjectTasksView(
                    // A new controller for each project.
                    key: ValueKey(selected.id),
                    project: selected,
                    api: widget.tasksApi,
                    sectionsApi: widget.sectionsApi,
                    token: widget.token,
                    moveTargets: () => widget.projects.projects,
                    showTitle: true,
                  );
            // Changing project fades through instead of cutting.
            final page = AnimatedSwitcher(
              duration: Motion.of(context, Motion.standard),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: content,
            );
            if (!wide) {
              // Full bleed: the list carries its own collapsing app bar,
              // with the drawer button, so nothing frames the list twice.
              return Scaffold(
                key: _scaffoldKey,
                appBar: selected == null
                    ? AppBar(title: const Text('فراش'))
                    : null,
                drawer: Drawer(child: _sidebar()),
                body: page,
              );
            }
            return Scaffold(
              key: _scaffoldKey,
              body: SafeArea(
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        12,
                        0,
                        12,
                      ),
                      child: SizedBox(
                        width: 288,
                        child: GlassSurface(child: _sidebar()),
                      ),
                    ),
                    Expanded(child: page),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

enum _AccountAction { calendar, logout }

/// The app's name with the account beneath it, and one menu for the
/// account's actions, so the email keeps its width.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.email, required this.onLogout});

  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'فراش',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<_AccountAction>(
            tooltip: 'حساب و تنظیمات',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (action) => switch (action) {
              _AccountAction.calendar => showCalendarSettings(
                context,
                CalendarScope.of(context),
              ),
              _AccountAction.logout => onLogout(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _AccountAction.calendar,
                child: ListTile(
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('تنظیمات تقویم'),
                ),
              ),
              PopupMenuItem(
                value: _AccountAction.logout,
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('خروج'),
                ),
              ),
            ],
          ),
        ],
      ),
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
