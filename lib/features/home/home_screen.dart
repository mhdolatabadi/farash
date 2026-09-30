import 'package:flutter/material.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/archived_projects_screen.dart';
import 'package:farash/features/projects/presentation/project_sidebar.dart';

/// Wide layouts keep the project list on screen; phones use a drawer.
const sidebarBreakpoint = 840.0;

/// The signed-in shell: project navigation and the selected project.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.projects,
  });

  final String email;
  final VoidCallback onLogout;
  final ProjectsController projects;

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
            final page = _ProjectPage(
              project: selected,
              loading: widget.projects.isLoading && selected == null,
            );
            if (!wide) {
              return Scaffold(
                key: _scaffoldKey,
                appBar: AppBar(title: Text(selected?.displayName ?? 'فراش')),
                drawer: Drawer(child: _sidebar()),
                body: page,
              );
            }
            return Scaffold(
              key: _scaffoldKey,
              body: Row(
                children: [
                  SizedBox(width: 300, child: _sidebar()),
                  const VerticalDivider(width: 1),
                  Expanded(
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
                ],
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
    return ListTile(
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
    );
  }
}

/// The selected project's page; its tasks arrive with #5.
class _ProjectPage extends StatelessWidget {
  const _ProjectPage({required this.project, required this.loading});

  final Project? project;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              project?.isInbox ?? true
                  ? Icons.inbox_outlined
                  : Icons.checklist_rtl,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'هنوز کاری در «${project?.displayName ?? 'صندوق ورودی'}» نیست.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
