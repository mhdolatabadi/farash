import 'package:farash/app/atelier.dart';
import 'package:farash/features/weaving/weaving_home.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/focus/focus_view.dart';
import 'package:flutter/material.dart';
import 'package:farash/features/progress/progress_card.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings_dialog.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/app/glass.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/archived_projects_screen.dart';
import 'package:farash/features/projects/presentation/project_sidebar.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';
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
    this.startView,
    this.labelsApi,
  });

  final String email;
  final VoidCallback onLogout;
  final ProjectsController projects;
  final TasksApi tasksApi;
  final SectionsApi? sectionsApi;

  /// Which list opens first; the Inbox when absent.
  final StartView? startView;

  /// Labels, where the backend offers them.
  final LabelsApi? labelsApi;

  /// The current access token; null once signed out.
  final String? Function() token;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedId;
  int _section = 1;
  final _focus = FocusController();

  /// A view across projects (امروز, پیش رو) instead of a project.
  DueView? _view;

  /// Open tasks due today or late, for the badge on «امروز».
  int? _todayCount;

  /// Whether the user has picked a list yet; until then the start view
  /// may still arrive from storage.
  bool _navigated = false;

  late final LabelsController? _labels = widget.labelsApi == null
      ? null
      : LabelsController(api: widget.labelsApi!, token: widget.token);

  /// The label whose tasks are open, if any.
  String? _labelId;

  @override
  void initState() {
    super.initState();
    widget.projects.load();
    _labels?.load();
    _applyStartView();
    widget.startView?.addListener(_applyStartView);
    _refreshCount();
  }

  @override
  void dispose() {
    _focus.dispose();
    widget.startView?.removeListener(_applyStartView);
    _labels?.dispose();
    super.dispose();
  }

  void _applyStartView() {
    final start = widget.startView;
    if (start == null || _navigated) return;
    final view = DueView.values.where((v) => v.name == start.value).firstOrNull;
    setState(() {
      _section = start.value == StartView.weaving ? 0 : 1;
      _view = view;
    });
  }

  Future<void> _refreshCount() async {
    final token = widget.token();
    if (token == null) return;
    try {
      final today = DateTime.now();
      final tasks = await widget.tasksApi.listDueTasks(
        token,
        to: DateTime(today.year, today.month, today.day),
      );
      if (mounted) setState(() => _todayCount = tasks.length);
    } catch (_) {
      // The badge is a hint; it stays as it was.
    }
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
    _navigated = true;
    _refreshCount();
    setState(() {
      _section = 1;
      _selectedId = project.id;
      _view = null;
      _labelId = null;
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _selectView(DueView view) {
    _navigated = true;
    _refreshCount();
    setState(() {
      _section = 1;
      _view = view;
      _labelId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => GlassLamp.placeFor('@${view.name}'),
    );
    _lampFor = null;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _selectLabel(Label label) {
    _navigated = true;
    setState(() {
      _section = 1;
      _labelId = label.id;
      _view = null;
    });
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

  void _switchSection(int section) {
    _navigated = true;
    setState(() => _section = section);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _startFocus(String? title) {
    if (_focus.running && _focus.taskTitle != title) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جلسهٔ قبلی هنوز در حال اجراست؛ ابتدا آن را مکث کنید.'),
        ),
      );
    }
    if (!_focus.running) {
      if (_focus.taskTitle != title || _focus.minutes != 25) _focus.choose(25);
      _focus.taskTitle = title;
    }
    _switchSection(2);
  }

  Widget _sidebar() => ProjectSidebar(
    controller: widget.projects,
    selectedId: _view == null && _labelId == null ? _selected?.id : null,
    labels: _labels,
    selectedLabelId: _labelId,
    onSelectLabel: _selectLabel,
    selectedView: _view,
    onSelect: _select,
    onSelectView: _selectView,
    viewCounts: {DueView.today: ?_todayCount},
    onOpenArchived: _openArchived,
    header: Column(
      children: [
        _AccountHeader(
          email: widget.email,
          onLogout: widget.onLogout,
          startView: widget.startView,
        ),
        if (MediaQuery.sizeOf(context).width >= sidebarBreakpoint) ...[
          for (final (index, icon, title) in [
            (0, Icons.grid_view_rounded, 'فرش'),
            (1, Icons.check_circle_outline_rounded, 'کارها'),
            (2, Icons.hourglass_empty_rounded, 'تمرکز'),
          ])
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Icon(icon),
                title: Text(title),
                selected: _section == index,
                onTap: () => _switchSection(index),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
        ],
        if (widget.tasksApi case final ApiClient api)
          ProgressCard(api: api, token: widget.token),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= sidebarBreakpoint;
        return ListenableBuilder(
          listenable: Listenable.merge([widget.projects, ?_labels]),
          builder: (context, _) {
            final selected = _selected;
            final view = _view;
            final label = _labels?.byId(_labelId);
            if (view == null && label == null) _placeLamp(selected);
            final Widget content = _section == 0
                ? WeavingHome(
                    key: const ValueKey('weaving-home'),
                    api: widget.tasksApi,
                    token: widget.token,
                    projects: widget.projects,
                    onTasks: () {
                      final inbox = widget.projects.inbox;
                      if (inbox != null) {
                        _select(inbox);
                      } else {
                        _switchSection(1);
                      }
                    },
                    onFocus: _startFocus,
                    onProject: (id) {
                      final p = widget.projects.byId(id);
                      if (p != null) {
                        _select(p);
                      } else {
                        _switchSection(1);
                      }
                    },
                  )
                : _section == 2
                ? FocusView(
                    key: const ValueKey('focus-view'),
                    controller: _focus,
                  )
                : label != null
                ? DueTasksView(
                    key: ValueKey('label-${label.id}'),
                    view: DueView.all,
                    label: label,
                    labels: _labels,
                    api: widget.tasksApi,
                    token: widget.token,
                    projects: () => widget.projects.projects,
                    onOpenProject: _select,
                  )
                : view != null
                ? DueTasksView(
                    key: ValueKey(view),
                    view: view,
                    api: widget.tasksApi,
                    token: widget.token,
                    projects: () => widget.projects.projects,
                    onOpenProject: _select,
                    labels: _labels,
                  )
                : selected == null
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
                    labels: _labels,
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
                appBar: selected == null && view == null && label == null
                    ? AppBar(title: const Text('فراش'))
                    : null,
                drawer: Drawer(child: _sidebar()),
                bottomNavigationBar: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: NavigationBar(
                    selectedIndex: _section,
                    onDestinationSelected: _switchSection,
                    destinations: const [
                      NavigationDestination(
                        icon: WeaveMark(size: 24),
                        selectedIcon: WeaveMark(size: 26),
                        label: 'فرش',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.check_circle_outline_rounded),
                        selectedIcon: Icon(Icons.check_circle_rounded),
                        label: 'کارها',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.hourglass_empty_rounded),
                        selectedIcon: Icon(Icons.hourglass_top_rounded),
                        label: 'تمرکز',
                      ),
                    ],
                  ),
                ),
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

enum _AccountAction { calendar, startView, logout }

/// The app's name with the account beneath it, and one menu for the
/// account's actions, so the email keeps its width.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.email,
    required this.onLogout,
    this.startView,
  });

  final String email;
  final VoidCallback onLogout;
  final StartView? startView;

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
                Row(
                  children: [
                    const WeaveMark(size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'فراش',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
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
              _AccountAction.startView => _pickStartView(context, startView!),
              _AccountAction.logout => onLogout(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _AccountAction.calendar,
                child: ListTile(
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('تنظیمات تقویم'),
                ),
              ),
              if (startView != null)
                const PopupMenuItem(
                  value: _AccountAction.startView,
                  child: ListTile(
                    leading: Icon(Icons.home_outlined),
                    title: Text('صفحهٔ آغاز'),
                  ),
                ),
              const PopupMenuItem(
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

/// Picks which list opens first on this device.
Future<void> _pickStartView(BuildContext context, StartView start) async {
  final choices = [
    (StartView.weaving, 'فرش'),
    (StartView.inbox, 'صندوق ورودی'),
    for (final v in DueView.values) (v.name, v.title),
  ];
  final picked = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('صفحهٔ آغاز'),
      children: [
        RadioGroup<String>(
          groupValue: start.value,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (value, label) in choices)
                RadioListTile<String>(value: value, title: Text(label)),
            ],
          ),
        ),
      ],
    ),
  );
  if (picked != null) await start.set(picked);
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
