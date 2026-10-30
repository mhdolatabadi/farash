import 'package:farash/features/calendar_connections/calendar_connections.dart';
import 'package:farash/features/calendar_connections/calendar_connections_view.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/habits/habits_view.dart';
import 'package:farash/features/habits/habit_detail.dart';
import 'package:farash/features/habits/reminders/habit_reminders.dart';
import 'package:farash/features/habits/reminders/local_reminders.dart';
import 'package:farash/features/search/search.dart';
import 'package:farash/features/search/search_view.dart';
import 'package:farash/features/portability/export_api.dart';
import 'package:farash/features/portability/export_dialog.dart';
import 'package:farash/features/scrum/scrum.dart';
import 'package:farash/features/scrum/scrum_view.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import 'package:farash/features/time_tracking/time_tracking_view.dart';
import 'package:farash/features/tasks/data/task.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/app/surfaces.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/focus/focus_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:farash/features/tasks/application/quick_capture.dart';
import 'package:farash/features/tasks/presentation/quick_add_dialog.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/progress/progress_card.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings_dialog.dart';
import 'package:farash/core/settings/start_view.dart';
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

/// Between phone and wide, the destinations move to a side rail.
const railBreakpoint = 600.0;

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
    this.habitReminders,
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

  /// The device's habit reminders, where the platform can show them.
  final HabitReminders? habitReminders;

  /// The current access token; null once signed out.
  final String? Function() token;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedId;
  int _section = 1;

  /// Where the app opens, and where Back returns to before leaving.
  int _startSection = 1;
  final _focus = FocusController();
  bool _focusWasFinished = false;
  late final TimeTracker? _tracker;

  /// Habits live in the shell so check-ins survive switching sections.
  late final HabitsController? _habits = widget.tasksApi is HabitsApi
      ? HabitsController(
          api: widget.tasksApi as HabitsApi,
          token: widget.token,
          reminders: widget.habitReminders,
        )
      : null;
  Task? _focusTask;
  String? _focusEntry;

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
    FocusManager.instance.addEarlyKeyEventHandler(_quickKey);
    _tracker = widget.tasksApi is TimeApi
        ? TimeTracker(api: widget.tasksApi as TimeApi, token: widget.token)
        : null;
    _tracker?.focusTask = _startTaskFocus;
    _tracker?.addListener(_trackerChanged);
    _focus.addListener(_focusChanged);
    if (widget.tasksApi case final ApiClient api) {
      api.completedTask.addListener(_completedTime);
      api.progressChanges.addListener(_refreshTracker);
    }
    widget.projects.load();
    _labels?.load();
    _startReminders();
    _applyStartView();
    widget.startView?.addListener(_applyStartView);
    _refreshCount();
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_quickKey);
    if (widget.tasksApi case final ApiClient api) {
      api.completedTask.removeListener(_completedTime);
      api.progressChanges.removeListener(_refreshTracker);
    }
    _tracker?.removeListener(_trackerChanged);
    _tracker?.dispose();
    _focus.removeListener(_focusChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.habitReminders?.opened.removeListener(_openReminder);
    if (widget.habitReminders case final LocalHabitReminders local) {
      local.onDone = null;
    }
    _habits?.dispose();
    _focus.dispose();
    widget.startView?.removeListener(_applyStartView);
    _labels?.dispose();
    super.dispose();
  }

  /// A finished session is announced wherever the user is, not only on
  /// the focus screen.
  void _focusChanged() {
    final finished = _focus.finished;
    if (finished && !_focusWasFinished && mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _focus.minutes == 25
                  ? 'جلسهٔ تمرکز تمام شد.'
                  : 'استراحت تمام شد.',
            ),
            action: _section == 2
                ? null
                : SnackBarAction(
                    label: 'تمرکز',
                    onPressed: () => _switchSection(2),
                  ),
          ),
        );
    }
    _focusWasFinished = finished;
  }

  bool _quickAdding = false;

  KeyEventResult _quickKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyQ ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isShiftPressed ||
        _quickAdding ||
        !mounted) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    // The shell remains mounted behind normal pages such as search. Keep
    // capture available there, but never steal keys from a modal editor.
    final route = ModalRoute.of(focused ?? context);
    if (route is PopupRoute || route?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    _quickAdd();
    return KeyEventResult.handled;
  }

  Future<void> _quickAdd() async {
    if (_quickAdding) return;
    final selected =
        ModalRoute.of(context)?.isCurrent == true &&
            _section == 1 &&
            _view == null &&
            _labelId == null
        ? _selected
        : null;
    final target =
        selected != null && !selected.isFolder && !selected.isArchived
        ? selected
        : widget.projects.inbox;
    if (target == null || target.isFolder || target.isArchived) return;
    _quickAdding = true;
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    final session = QuickCaptureSession(
      api: widget.tasksApi,
      sections: widget.sectionsApi,
      labels: _labels,
      token: widget.token,
      projects: () => widget.projects.projects,
      defaultProject: () => target,
    );
    try {
      final task = await showDialog<Task>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            QuickAddDialog(projectName: target.displayName, session: session),
      );
      if (task != null && mounted) {
        _refreshCount();
        // Recreate the selected task page so the confirmed task appears.
        setState(() => _captureRevision++);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('«${task.title}» اضافه شد.')));
      }
    } finally {
      _quickAdding = false;
    }
  }

  int _captureRevision = 0;

  void _refreshTracker() {
    _tracker?.load();
  }

  void _trackerChanged() {
    if (_focusEntry != null && _tracker?.active?.id != _focusEntry) {
      _focus.pause();
      _focusEntry = null;
    }
  }

  void _startTaskFocus(Task task) {
    if (_focus.running) {
      _startFocus(task.title);
      return;
    }
    _startFocus(task.title);
    _focusTask = task;
  }

  Future<bool> _beforeFocusStart() async {
    final tracker = _tracker, task = _focusTask;
    if (tracker == null || task == null || _focus.minutes != 25) return true;
    if (tracker.active case final active?) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ثبت زمان دیگری فعال است'),
          content: Text(
            'ثبت «${active.title}» متوقف و تمرکز روی «${task.title}» شروع شود؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('توقف و شروع'),
            ),
          ],
        ),
      );
      if (yes != true || !await tracker.stop(active)) return false;
    }
    final ok = await tracker.start(
      task,
      focusSeconds: _focus.remaining.inSeconds.clamp(1, 1500),
    );
    if (ok) {
      _focusEntry = tracker.active?.id;
      final end = tracker.active?.plannedEnd;
      if (end != null) {
        final remaining = end.difference(tracker.now);
        if (remaining <= Duration.zero) {
          await tracker.load();
          return false;
        }
        _focus.restoreRemaining(remaining);
      }
    }
    return ok;
  }

  Future<bool> _beforeFocusPause() async {
    final active = _tracker?.active;
    if (active != null && active.id == _focusEntry) {
      return _tracker!.stop(active);
    }
    return true;
  }

  Future<void> _completedTime() async {
    final tracker = _tracker;
    if (tracker == null) return;
    final task = (widget.tasksApi as ApiClient).completedTask.value;
    if (task == null) return;
    await tracker.load();
    try {
      final report = await tracker.fetch(taskId: task.id);
      if (!mounted || report.seconds > 0 || report.entries.isNotEmpty) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'برای «${task.title}» چقدر وقت گذاشتید؟',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in [15, 30, 60])
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final end = DateTime.now();
                        await tracker.save(
                          task,
                          end.subtract(Duration(minutes: minutes)),
                          end,
                          timeKey(),
                        );
                      },
                      child: Text('${persianDigits(minutes)} دقیقه'),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      manualTime(context, tracker, task);
                    },
                    child: const Text('ورود دستی'),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('فعلاً نه'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      /* Completion remains successful when time reporting is unavailable. */
    }
  }

  void _applyStartView() {
    final start = widget.startView;
    if (start == null || _navigated) return;
    final today = start.value == StartView.today;
    final view = today
        ? null
        : DueView.values.where((v) => v.name == start.value).firstOrNull;
    setState(() {
      _section = _startSection = today ? 0 : 1;
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
    // Today has its own destination; the other views open under کارها.
    final today = view == DueView.today;
    setState(() {
      _section = today ? 0 : 1;
      _view = today ? null : view;
      _labelId = null;
    });
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

  /// Reminders need the habits even before their tab is opened, and again
  /// on return, when a reminder may have been answered in the background.
  void _startReminders() {
    final reminders = widget.habitReminders;
    final habits = _habits;
    if (reminders == null || habits == null) return;
    WidgetsBinding.instance.addObserver(this);
    reminders.opened.addListener(_openReminder);
    if (reminders case final LocalHabitReminders local) {
      local.onDone = habits.markDone;
      local.start();
    }
    habits.load().then((_) => _openReminder());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _habits?.load();
  }

  /// Shows the habit of a reminder the user tapped.
  void _openReminder() {
    final reminders = widget.habitReminders;
    final habits = _habits;
    final id = reminders?.opened.value;
    if (reminders == null || habits == null || id == null) return;
    if (habits.byId(id) == null || !mounted) return;
    reminders.opened.value = null;
    _switchSection(4);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitDetailScreen(controller: habits, habitId: id),
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
      _focusTask = null;
      if (_focus.taskTitle != title || _focus.minutes != 25) _focus.choose(25);
      _focus.taskTitle = title;
    }
    _switchSection(2);
  }

  /// The remaining time while a session runs, for the focus destination.
  String? get _focusBadge {
    if (!_focus.running) return null;
    final seconds = _focus.remaining.inSeconds;
    return persianDigits(
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
    );
  }

  /// The top-level destinations, shared by the bottom bar and the rail.
  List<(Widget icon, Widget selectedIcon, String label)> _destinations() {
    final badge = _focusBadge;
    Widget focusIcon(IconData data) => Badge(
      isLabelVisible: badge != null,
      label: Text(badge ?? ''),
      child: Icon(data),
    );
    return [
      (
        const Icon(Icons.today_outlined),
        const Icon(Icons.today_rounded),
        'امروز',
      ),
      (
        const Icon(Icons.check_circle_outline_rounded),
        const Icon(Icons.check_circle_rounded),
        'کارها',
      ),
      (
        focusIcon(Icons.timelapse_outlined),
        focusIcon(Icons.timelapse_rounded),
        'تمرکز',
      ),
      if (_tracker != null)
        (
          const Icon(Icons.timer_outlined),
          const Icon(Icons.timer_rounded),
          'زمان‌ها',
        ),
      if (_habits != null)
        (
          const Icon(Icons.task_alt_outlined),
          const Icon(Icons.task_alt_rounded),
          'عادت‌ها',
        ),
    ];
  }

  /// Today, Focus and Habits sit on the soft ground.
  bool get _softSection =>
      _section == 0 || _section == 2 || (_section == 4 && _habits != null);

  /// Tasks the server counts as completed today, from the progress
  /// report; null when the report has no such day.
  Future<int?> _doneToday() async {
    final api = widget.tasksApi;
    final token = widget.token();
    if (api is! ApiClient || token == null) return null;
    final progress = await api.loadProgress(token, await deviceTimeZone());
    final now = DateTime.now();
    for (final day in progress.weekReport?.days ?? const <ProgressDay>[]) {
      if (day.date.year == now.year &&
          day.date.month == now.month &&
          day.date.day == now.day) {
        return day.completed;
      }
    }
    return null;
  }

  /// The sections behind the phone's bottom destinations, in order.
  List<int> get _navSections => [
    0,
    1,
    2,
    if (_tracker != null) 3,
    if (_habits != null) 4,
  ];

  void _openSearch(SearchApi api) {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackerScope(
          tracker: _tracker,
          child: SearchWorkspace(
            api: api,
            tasks: widget.tasksApi,
            sections: widget.sectionsApi,
            labels: _labels,
            token: widget.token,
            projects: () => widget.projects.projects,
          ),
        ),
      ),
    );
  }

  Widget _sidebar() => ProjectSidebar(
    controller: widget.projects,
    selectedId: _section == 1 && _view == null && _labelId == null
        ? _selected?.id
        : null,
    labels: _labels,
    selectedLabelId: _labelId,
    onSelectLabel: _selectLabel,
    selectedView: _section == 0
        ? DueView.today
        : (_section == 1 ? _view : null),
    onSelect: _select,
    onSelectView: _selectView,
    viewCounts: {DueView.today: ?_todayCount},
    onOpenArchived: _openArchived,
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Brand(),
        if (widget.tasksApi case final SearchApi api)
          _SearchField(onTap: () => _openSearch(api)),
      ],
    ),
    account: _AccountRow(
      calendarConnectionsApi: widget.tasksApi is CalendarConnectionsApi
          ? widget.tasksApi as CalendarConnectionsApi
          : null,
      email: widget.email,
      onLogout: widget.onLogout,
      startView: widget.startView,
      exportApi: widget.tasksApi is ExportApi
          ? widget.tasksApi as ExportApi
          : null,
      token: widget.token,
    ),
    // On a phone these are already in the bottom bar.
    tools: MediaQuery.sizeOf(context).width >= sidebarBreakpoint
        ? [
            for (final (index, icon, title) in [
              (2, Icons.timelapse_outlined, 'تمرکز'),
              if (_tracker != null) (3, Icons.timer_outlined, 'زمان‌ها'),
              if (_habits != null) (4, Icons.task_alt_rounded, 'عادت‌ها'),
            ])
              SidebarRow(
                selected: _section == index,
                child: ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  trailing: index == 2 && _focusBadge != null
                      ? Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: Text(_focusBadge!),
                        )
                      : null,
                  selected: _section == index,
                  onTap: () => _switchSection(index),
                ),
              ),
          ]
        : null,
    footer: switch (widget.tasksApi) {
      final ApiClient api => ProgressCard(api: api, token: widget.token),
      _ => null,
    },
  );

  @override
  Widget build(BuildContext context) {
    // Back steps out to the start destination before it leaves the app.
    return PopScope(
      canPop: _section == _startSection,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _switchSection(_startSection);
      },
      child: _layout(),
    );
  }

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= sidebarBreakpoint;
        final rail = !wide && constraints.maxWidth >= railBreakpoint;
        return ListenableBuilder(
          listenable: Listenable.merge([widget.projects, ?_labels]),
          builder: (context, _) {
            final selected = _selected;
            final view = _view;
            final label = _labels?.byId(_labelId);
            final Widget content = _section == 0
                ? DueTasksView(
                    key: const ValueKey(DueView.today),
                    view: DueView.today,
                    api: widget.tasksApi,
                    token: widget.token,
                    projects: () => widget.projects.projects,
                    onOpenProject: _select,
                    labels: _labels,
                    sectionsApi: widget.sectionsApi,
                    doneToday: widget.tasksApi is ApiClient ? _doneToday : null,
                    focus: _focus,
                    onOpenFocus: () => _switchSection(2),
                    habits: _habits,
                    onOpenHabits: _habits == null
                        ? null
                        : () => _switchSection(4),
                  )
                : _section == 2
                ? FocusView(
                    key: const ValueKey('focus-view'),
                    controller: _focus,
                    beforeStart: _beforeFocusStart,
                    beforePause: _beforeFocusPause,
                    timeLinked: _tracker != null && _focusTask != null,
                  )
                : _section == 4 && _habits != null
                ? HabitsView(
                    key: const ValueKey('habits-view'),
                    controller: _habits,
                  )
                : _section == 3 && _tracker != null
                ? TimeTrackingView(
                    tracker: _tracker,
                    tasksApi: widget.tasksApi,
                    projects: widget.projects,
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
                    sectionsApi: widget.sectionsApi,
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
                    sectionsApi: widget.sectionsApi,
                  )
                : selected == null
                ? _ProjectPage(loading: widget.projects.isLoading)
                : widget.tasksApi is ScrumApi &&
                      !selected.isInbox &&
                      !selected.isFolder
                ? ProjectWorkspace(
                    key: ValueKey('workspace-${selected.id}'),
                    project: selected,
                    api: widget.tasksApi as ScrumApi,
                    tasks: widget.tasksApi,
                    token: widget.token,
                    projects: () => widget.projects.projects,
                    simple: ProjectTasksView(
                      key: ValueKey(selected.id),
                      project: selected,
                      api: widget.tasksApi,
                      sectionsApi: widget.sectionsApi,
                      token: widget.token,
                      moveTargets: () => widget.projects.projects,
                      labels: _labels,
                    ),
                  )
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
            final page = TrackerScope(
              tracker: _tracker,
              child: AnimatedSwitcher(
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
              ),
            );
            if (!wide) {
              // Full bleed: the list carries its own collapsing app bar,
              // with the drawer button, so nothing frames the list twice.
              return Scaffold(
                key: _scaffoldKey,
                appBar: selected == null && view == null && label == null
                    ? AppBar(title: const Text('فراش'))
                    : null,
                drawer: Drawer(
                  backgroundColor: Soft.ground(context),
                  child: _sidebar(),
                ),
                bottomNavigationBar: rail
                    ? null
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          // The soft destinations carry their ground down
                          // under the bar.
                          color: _softSection
                              ? Soft.ground(context)
                              : Theme.of(context).colorScheme.surface,
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: ListenableBuilder(
                          listenable: _focus,
                          builder: (context, _) => NavigationBar(
                            backgroundColor: _softSection
                                ? Soft.ground(context)
                                : null,
                            selectedIndex: _navSections.indexOf(_section),
                            onDestinationSelected: (i) =>
                                _switchSection(_navSections[i]),
                            destinations: [
                              for (final (icon, selectedIcon, label)
                                  in _destinations())
                                NavigationDestination(
                                  icon: icon,
                                  selectedIcon: selectedIcon,
                                  label: label,
                                ),
                            ],
                          ),
                        ),
                      ),
                body: Row(
                  children: [
                    if (rail) ...[
                      SafeArea(
                        right: false,
                        left: false,
                        child: ListenableBuilder(
                          listenable: _focus,
                          builder: (context, _) => NavigationRail(
                            selectedIndex: _navSections.indexOf(_section),
                            onDestinationSelected: (i) =>
                                _switchSection(_navSections[i]),
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: 0,
                            destinations: [
                              for (final (icon, selectedIcon, label)
                                  in _destinations())
                                NavigationRailDestination(
                                  icon: icon,
                                  selectedIcon: selectedIcon,
                                  label: Text(label),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: Column(
                        children: [
                          if (_tracker != null)
                            ActiveTimeBar(
                              tracker: _tracker,
                              onOpen: () => _switchSection(3),
                            ),
                          if (_tracker != null)
                            TrackerMessage(tracker: _tracker),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey(_captureRevision),
                              child: page,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            return Scaffold(
              key: _scaffoldKey,
              body: SafeArea(
                child: Row(
                  children: [
                    // The sidebar lies on the same ground as the page, set
                    // off by one hairline; only the open row stands up.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: BorderDirectional(end: Soft.hairline(context)),
                      ),
                      child: SizedBox(
                        width: 264,
                        child: ListenableBuilder(
                          listenable: _focus,
                          builder: (context, _) => _sidebar(),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          if (_tracker != null)
                            ActiveTimeBar(
                              tracker: _tracker,
                              onOpen: () => _switchSection(3),
                            ),
                          if (_tracker != null)
                            TrackerMessage(tracker: _tracker),
                          Expanded(
                            child: KeyedSubtree(
                              key: ValueKey(_captureRevision),
                              child: page,
                            ),
                          ),
                        ],
                      ),
                    ),
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

enum _AccountAction { calendar, calendarConnections, startView, export, logout }

/// The app's mark and name at the top of the sidebar.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.md,
        Space.xs,
        Space.md,
        Space.md,
      ),
      child: Row(
        children: [
          const FarashMark(size: 22),
          const SizedBox(width: Space.sm),
          Text(
            'فراش',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// The account at the bottom of the sidebar: the initial and the email,
/// one row whose menu holds the account's actions.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.email,
    required this.onLogout,
    this.startView,
    this.exportApi,
    this.calendarConnectionsApi,
    required this.token,
  });

  final String email;
  final VoidCallback onLogout;
  final StartView? startView;
  final ExportApi? exportApi;
  final CalendarConnectionsApi? calendarConnectionsApi;
  final String? Function() token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final initial = email.isEmpty ? '?' : email.characters.first.toUpperCase();
    return PopupMenuButton<_AccountAction>(
      tooltip: 'حساب و تنظیمات',
      position: PopupMenuPosition.over,
      borderRadius: BorderRadius.circular(SidebarRow.radius),
      // The tooltip names the button; the initial and email are what it
      // shows, not what it is called.
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(
                  initial,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(Icons.unfold_more, size: 18, color: muted),
            ],
          ),
        ),
      ),
      onSelected: (action) => switch (action) {
        _AccountAction.calendar => showCalendarSettings(
          context,
          CalendarScope.of(context),
        ),
        _AccountAction.calendarConnections => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CalendarConnectionsView(
              api: calendarConnectionsApi!,
              token: token,
            ),
          ),
        ),
        _AccountAction.startView => _pickStartView(context, startView!),
        _AccountAction.export => showAccountExport(context, exportApi!, token),
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
        if (calendarConnectionsApi != null)
          const PopupMenuItem(
            value: _AccountAction.calendarConnections,
            child: ListTile(
              leading: Icon(Icons.event_available_outlined),
              title: Text('اتصال تقویم‌ها'),
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
        if (exportApi != null)
          const PopupMenuItem(
            value: _AccountAction.export,
            child: ListTile(
              leading: Icon(Icons.download_outlined),
              title: Text('خروجی داده‌های من'),
            ),
          ),
        const PopupMenuItem(
          value: _AccountAction.logout,
          child: ListTile(leading: Icon(Icons.logout), title: Text('خروج')),
        ),
      ],
    );
  }
}

/// Search as a field sunk into the ground; it opens the search page.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.zero,
      child: Semantics(
        container: true,
        button: true,
        label: 'جست‌وجو و فیلترها',
        excludeSemantics: true,
        child: SoftWell(
          radius: SidebarRow.radius,
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, size: 18, color: muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'جست‌وجو',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks which list opens first on this device.
Future<void> _pickStartView(BuildContext context, StartView start) async {
  final choices = [
    (StartView.today, DueView.today.title),
    (StartView.inbox, 'صندوق ورودی'),
    for (final v in DueView.values)
      if (v != DueView.today) (v.name, v.title),
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
