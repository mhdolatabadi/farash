import 'dart:async';

import 'package:menval/app/app_configuration.dart';
import 'package:menval/features/focus/focus_session_storage.dart';
import 'package:menval/features/calendar/task_calendar_view.dart';
import 'package:menval/features/calendar_connections/calendar_connections.dart';
import 'package:menval/features/calendar_connections/calendar_connections_view.dart';
import 'package:menval/features/habits/habits_controller.dart';
import 'package:menval/features/habits/habits_view.dart';
import 'package:menval/features/habits/habit_detail.dart';
import 'package:menval/features/habits/habit_editor.dart';
import 'package:menval/features/habits/reminders/habit_reminders.dart';
import 'package:menval/features/habits/reminders/local_reminders.dart';
import 'package:menval/features/habits/reminders/task_due_preference.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/features/matrix/matrix.dart';
import 'package:menval/features/matrix/matrix_view.dart';
import 'package:menval/features/search/filter_editor.dart';
import 'package:menval/features/search/search.dart';
import 'package:menval/features/search/search_view.dart';
import 'package:menval/features/portability/export_api.dart';
import 'package:menval/features/portability/export_dialog.dart';
import 'package:menval/features/scrum/scrum.dart';
import 'package:menval/features/scrum/scrum_view.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/time_tracking/time_tracking.dart';
import 'package:menval/features/time_tracking/time_tracking_view.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/widgets/hover_reveal.dart';
import 'package:menval/app/surfaces.dart';
import 'package:menval/features/focus/focus_controller.dart';
import 'package:menval/features/focus/focus_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:menval/features/tasks/application/quick_capture.dart';
import 'package:menval/features/tasks/data/quick_parse.dart';
import 'package:menval/features/tasks/presentation/quick_add_dialog.dart';
import 'package:menval/features/progress/progress.dart';
import 'package:menval/features/progress/progress_card.dart';
import 'package:menval/core/calendar/time_zone.dart';
import 'package:menval/app/motion.dart';
import 'package:menval/app/press_depth.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings_dialog.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:menval/features/labels/application/labels_controller.dart';
import 'package:menval/features/labels/data/label.dart';
import 'package:menval/features/projects/application/projects_controller.dart';
import 'package:menval/features/projects/data/project.dart';
import 'package:menval/features/projects/presentation/archived_projects_screen.dart';
import 'package:menval/features/projects/presentation/project_sidebar.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/features/tasks/presentation/due_tasks_view.dart';
import 'package:menval/features/tasks/presentation/project_tasks_view.dart';

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
    this.habitReminders,
    this.settingsStore,
    this.focusSessionStorage,
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

  /// Where device-only choices such as the matrix rules are kept; the
  /// secure device store when null.
  final CalendarSettingsStore? settingsStore;

  /// Optional injectable store for deterministic restart tests.
  final FocusSessionStorage? focusSessionStorage;

  /// The current access token; null once signed out.
  final String? Function() token;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedId;
  int _section = 0;

  /// Where the app opens, and where Back returns to before leaving.
  int _startSection = 0;
  final _focus = FocusController();
  late final FocusSessionStorage _focusStorage =
      widget.focusSessionStorage ??
      FocusSessionStorage(
        account: widget.email,
        server: AppConfiguration.apiBaseUri?.origin ?? 'local',
      );
  Future<void> _focusWrites = Future<void>.value();
  String? _lastFocusPayload;
  bool _restoringFocus = true;
  bool _signingOut = false;
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

  late final FiltersController? _filters = switch (widget.tasksApi) {
    final SearchApi api => FiltersController(api: api, token: widget.token),
    _ => null,
  };

  /// Task reminder consent is opt-in, device-only and stays separate from
  /// the habit notification permission. No task contents are persisted here.
  late final CalendarSettingsStore _notificationStore =
      widget.settingsStore ?? SecureCalendarSettingsStore();
  late final TaskDueNotificationPreference _taskDuePreference =
      TaskDueNotificationPreference(
        account: widget.email,
        server: AppConfiguration.apiBaseUri?.origin ?? 'local',
        store: _notificationStore,
      );
  bool _taskDueNotificationsOn = false;
  int _taskDueSyncGeneration = 0;

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
    unawaited(_restoreFocus());
    if (widget.tasksApi case final ApiClient api) {
      api.completedTask.addListener(_completedTime);
      api.progressChanges.addListener(_refreshTracker);
      api.progressChanges.addListener(_taskDataChanged);
    }
    widget.projects.addListener(_openTaskDueReminder);
    widget.projects.load();
    _labels?.load();
    _filters?.load();
    _startReminders();
    if (widget.habitReminders is LocalHabitReminders) {
      unawaited(_loadTaskDuePreference());
    }
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
      api.progressChanges.removeListener(_taskDataChanged);
    }
    widget.projects.removeListener(_openTaskDueReminder);
    _tracker?.removeListener(_trackerChanged);
    _tracker?.dispose();
    _focus.removeListener(_focusChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.habitReminders?.opened.removeListener(_openReminder);
    if (widget.habitReminders case final LocalHabitReminders local) {
      local.onDone = null;
      local.openedTaskProject.removeListener(_openTaskDueReminder);
    }
    ++_taskDueSyncGeneration;
    _inlineTask.dispose();
    _habits?.dispose();
    _focus.dispose();
    widget.startView?.removeListener(_applyStartView);
    _labels?.dispose();
    _matrix?.dispose();
    _filters?.dispose();
    super.dispose();
  }

  /// Restore only local focus presentation. Server entries remain the source
  /// of truth for linked work; a missing/disconnected entry pauses focus.
  Future<void> _restoreFocus() async {
    final saved = await _focusStorage.read();
    if (!mounted || _signingOut) return;
    if (saved != null &&
        !_focus.running &&
        _focus.taskTitle == null &&
        _focus.minutes == 25 &&
        _focus.remaining == const Duration(minutes: 25)) {
      DateTime? deadline = saved.deadlineMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(saved.deadlineMs!);
      var remaining = Duration(milliseconds: saved.remainingMs);
      var finished = saved.finished;
      if (saved.entryId != null && deadline != null) {
        await _tracker?.load();
        if (!mounted || _signingOut) return;
        if (_tracker?.error == null &&
            _tracker?.active?.id == saved.entryId &&
            _tracker?.active?.source == 'focus') {
          _focusEntry = saved.entryId;
        } else {
          // Do not imply that offline or server-ended work is still tracked.
          final left = deadline.difference(DateTime.now());
          remaining = left > Duration.zero ? left : Duration.zero;
          finished = left <= Duration.zero;
          deadline = null;
        }
      }
      if (saved.taskId != null) {
        _focusTask = Task(
          id: saved.taskId!,
          projectId: '',
          title: saved.taskTitle ?? '',
        );
      }
      _focus.restoreState(
        mode: saved.minutes,
        remaining: remaining,
        deadline: deadline,
        title: saved.taskTitle,
        wasFinished: finished,
      );
      _focusWasFinished = _focus.finished;
    }
    _restoringFocus = false;
    _persistFocus();
  }

  void _persistFocus() {
    if (_restoringFocus || _signingOut) return;
    final state = FocusSessionData(
      minutes: _focus.minutes,
      remainingMs: _focus.running ? 0 : _focus.remaining.inMilliseconds,
      deadlineMs: _focus.deadline?.millisecondsSinceEpoch,
      taskTitle: _focus.taskTitle,
      taskId: _focusTask?.id,
      entryId: _focusEntry,
      finished: _focus.finished,
    );
    final payload = state.encode();
    if (_lastFocusPayload == payload) return; // Not once per timer tick.
    _lastFocusPayload = payload;
    _focusWrites = _focusWrites
        .then((_) => _focusStorage.save(state))
        .catchError((_) {});
  }

  Future<void> _signOutFromHome() async {
    if (_signingOut) return;
    _signingOut = true;
    // Sign-out is a primary navigation action, never wait for local storage.
    // Queue deletion after older writes so they cannot resurrect the snapshot.
    widget.onLogout();
    await _focusWrites;
    try {
      await _focusStorage.save(null);
    } catch (_) {
      // Logout already took effect, even with unavailable device storage.
    }
  }

  /// A finished session is announced wherever the user is, not only on
  /// the focus screen.
  void _focusChanged() {
    final finished = _focus.finished;
    if (!_restoringFocus && finished && !_focusWasFinished && mounted) {
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
    _persistFocus();
  }

  bool _quickAdding = false;
  final _inlineTask = TextEditingController();

  KeyEventResult _quickKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyK &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        mounted) {
      final route = ModalRoute.of(
        FocusManager.instance.primaryFocus?.context ?? context,
      );
      if (widget.tasksApi case final SearchApi api
          when route is! PopupRoute && route?.isCurrent == true) {
        _openSearch(api);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
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

  Future<void> _quickAdd({String? initialText}) async {
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
      final task = await showModalBottomSheet<Task>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black.withValues(alpha: 0.16),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: QuickAddDialog(
            projectName: target.displayName,
            session: session,
            initialText: initialText ?? '',
          ),
        ),
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

  Future<void> _submitInline() async {
    final raw = _inlineTask.text.trim();
    if (raw.isEmpty || _quickAdding) return;
    final selected = _section == 1 && _view == null && _labelId == null
        ? _selected
        : null;
    final target =
        selected != null && !selected.isFolder && !selected.isArchived
        ? selected
        : widget.projects.inbox;
    if (target == null || target.isFolder || target.isArchived) return;
    _quickAdding = true;
    try {
      final session = QuickCaptureSession(
        api: widget.tasksApi,
        sections: widget.sectionsApi,
        labels: _labels,
        token: widget.token,
        projects: () => widget.projects.projects,
        defaultProject: () => target,
      );
      await session.capture(
        parseQuickTask(raw, now: DateTime.now()),
        raw,
        calendar: CalendarScope.of(context).isJalali ? 'jalali' : 'gregorian',
        defaultDay: _section == 0 ? DateTime.now() : null,
      );
      if (!mounted) return;
      _inlineTask.clear();
      _refreshCount();
      setState(() => _captureRevision++);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('کار اضافه شد.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _quickAdding = false;
    }
  }

  Widget _captureBar() {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 10),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Material(
              color: colors.surface,
              elevation: 3,
              shadowColor: colors.shadow.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.xs,
                        end: Space.sm,
                      ),
                      child: Text(
                        'منوال',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    PressDepth(
                      child: PopupMenuButton<String>(
                        key: const ValueKey('compact-navigation'),
                        tooltip: 'بخش‌ها',
                        icon: const Icon(Icons.apps_outlined, size: 20),
                        onSelected: (choice) {
                          if (choice == 'tasks') {
                            _switchSection(1);
                          } else if (choice == 'today') {
                            _switchSection(0);
                          } else if (choice == 'calendar') {
                            _openNativeCalendar();
                          } else if (choice == 'habits') {
                            _switchSection(4);
                          } else if (choice == 'focus') {
                            _switchSection(2);
                          } else if (choice == 'times') {
                            _switchSection(3);
                          } else if (choice == 'more') {
                            _scaffoldKey.currentState?.openDrawer();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'tasks',
                            child: Text('کارها'),
                          ),
                          const PopupMenuItem(
                            value: 'calendar',
                            child: Text('تقویم'),
                          ),
                          if (_habits != null)
                            const PopupMenuItem(
                              value: 'habits',
                              child: Text('عادت‌ها'),
                            ),
                          const PopupMenuItem(
                            value: 'today',
                            child: Text('امروز'),
                          ),
                          const PopupMenuItem(
                            value: 'focus',
                            child: Text('تمرکز'),
                          ),
                          if (_tracker != null)
                            const PopupMenuItem(
                              value: 'times',
                              child: Text('زمان‌ها'),
                            ),
                          const PopupMenuItem(
                            value: 'more',
                            child: Text('بخش‌های بیشتر'),
                          ),
                        ],
                      ),
                    ),
                    PressDepth(
                      child: IconButton(
                        key: const ValueKey('quick-add-more'),
                        tooltip: 'تاریخ و ساعت کار',
                        onPressed: () =>
                            _quickAdd(initialText: _inlineTask.text.trim()),
                        icon: const Icon(Icons.schedule_outlined, size: 20),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('inline-task-title'),
                        controller: _inlineTask,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitInline(),
                        decoration: const InputDecoration(
                          hintText: 'کار جدید…',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6),
                        ),
                      ),
                    ),
                    PressDepth(
                      child: IconButton.filled(
                        key: const ValueKey('inline-task-submit'),
                        tooltip: 'ثبت کار',
                        onPressed: _submitInline,
                        icon: const Icon(
                          Icons.keyboard_return_rounded,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<List<Task>> _loadCalendarTasks(DateTime from, DateTime to) async {
    final token = widget.token();
    if (token == null) throw StateError('Session unavailable');
    final tasks = await widget.tasksApi.listDueTasks(token, from: from, to: to);
    if (widget.token() != token) throw StateError('Session changed');
    return tasks;
  }

  void _openNativeCalendar() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
    _switchSection(5);
  }

  Future<void> _createHabitFromFab() async {
    final controller = _habits;
    if (controller == null) return;
    final habit = await createHabit(context, controller);
    if (!mounted || habit == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('«${habit.name}» اضافه شد.')));
  }

  Widget _approvedNav() {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.md,
          Space.xs,
          Space.md,
          Space.md,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Soft.ground(context),
                borderRadius: BorderRadius.circular(26),
                boxShadow: Soft.raised(context, depth: 3),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Space.xs),
                child: Row(
                  children: [
                    for (final (section, label, icon) in [
                      (0, 'کارها', Icons.format_list_bulleted_rounded),
                      (5, 'تقویم', Icons.calendar_month_outlined),
                      (4, 'عادت‌ها', Icons.check_circle_outline_rounded),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Semantics(
                            button: true,
                            selected: section == 0
                                ? _section == 0 || _section == 1
                                : _section == section,
                            child: PressDepth(
                              enabled: section != 4 || _habits != null,
                              child: InkWell(
                                key: ValueKey('approved-nav-$section'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: section == 4 && _habits == null
                                    ? null
                                    : () => _switchSection(section),
                                child:
                                    (section == 0
                                        ? _section == 0 || _section == 1
                                        : _section == section)
                                    ? SoftWell(
                                        radius: 20,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Space.sm,
                                          horizontal: Space.xs,
                                        ),
                                        child: _navLabel(
                                          icon,
                                          label,
                                          colors.onSurface,
                                          true,
                                        ),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: Space.sm,
                                          horizontal: Space.xs,
                                        ),
                                        child: _navLabel(
                                          icon,
                                          label,
                                          colors.onSurfaceVariant,
                                          false,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navLabel(IconData icon, String text, Color color, bool selected) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: Space.xs),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      );

  int _captureRevision = 0;

  void _refreshTracker() {
    _tracker?.load();
  }

  void _trackerChanged() {
    if (_focusEntry != null && _tracker?.active?.id != _focusEntry) {
      _focus.pause();
      _focusEntry = null;
      _persistFocus();
    }
  }

  void _startTaskFocus(Task task) {
    if (_focus.running) {
      _startFocus(task.title);
      return;
    }
    _startFocus(task.title);
    _focusTask = task;
    _persistFocus();
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
      _persistFocus();
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
      local.openedTaskProject.addListener(_openTaskDueReminder);
      local.start();
    }
    habits.load().then((_) {
      _openReminder();
      _openTaskDueReminder();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _focus.refresh();
      _habits?.load();
      _taskDataChanged();
    }
  }

  Future<void> _loadTaskDuePreference() async {
    try {
      final enabled = await _taskDuePreference.read();
      if (!mounted || _signingOut || !enabled) return;
      setState(() => _taskDueNotificationsOn = true);
      await _syncTaskDues();
    } catch (_) {
      // Unavailable settings storage means reminders remain opt-in.
    }
  }

  void _taskDataChanged() {
    if (_taskDueNotificationsOn) unawaited(_syncTaskDues());
  }

  Future<void> _syncTaskDues() async {
    if (!_taskDueNotificationsOn ||
        _signingOut ||
        widget.habitReminders is! LocalHabitReminders) {
      return;
    }
    final generation = ++_taskDueSyncGeneration;
    final token = widget.token();
    if (token == null) return;
    try {
      final now = DateTime.now();
      final tasks = await widget.tasksApi.listDueTasks(
        token,
        from: now,
        to: now.add(const Duration(days: 14)),
      );
      if (!mounted ||
          _signingOut ||
          !_taskDueNotificationsOn ||
          generation != _taskDueSyncGeneration ||
          token != widget.token() ||
          (widget.tasksApi is ApiClient &&
              (widget.tasksApi as ApiClient).isOffline)) {
        return;
      }
      await (widget.habitReminders as LocalHabitReminders).syncTaskDues(tasks);
    } catch (_) {
      // Preserve existing alarms on transport or server failures.
    }
  }

  Future<void> _toggleTaskDueNotifications() async {
    final reminders = widget.habitReminders;
    if (reminders is! LocalHabitReminders) return;
    if (_taskDueNotificationsOn) {
      ++_taskDueSyncGeneration;
      setState(() => _taskDueNotificationsOn = false);
      try {
        await _taskDuePreference.write(false);
      } catch (_) {}
      await reminders.clearTaskDues();
      return;
    }
    final permitted = await reminders.requestPermission();
    if (!mounted || _signingOut) return;
    if (!permitted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'برای اعلان سررسید، اجازهٔ اعلان‌ها را در تنظیمات دستگاه فعال کنید.',
          ),
        ),
      );
      return;
    }
    setState(() => _taskDueNotificationsOn = true);
    try {
      await _taskDuePreference.write(true);
    } catch (_) {}
    await _syncTaskDues();
  }

  void _openTaskDueReminder() {
    final reminders = widget.habitReminders;
    if (reminders is! LocalHabitReminders || !mounted) return;
    final projectId = reminders.openedTaskProject.value;
    if (projectId == null) return;
    final project = widget.projects.byId(projectId);
    if (project == null) return;
    reminders.openedTaskProject.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_signingOut) _select(project);
    });
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
      _persistFocus();
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

  MatrixRules? _matrix;
  MatrixRules get _matrixRules => _matrix ??= MatrixRules(
    store: widget.settingsStore ?? SecureCalendarSettingsStore(),
  )..load();

  void _openMatrix(SearchApi api) {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrackerScope(
          tracker: _tracker,
          child: MatrixView(
            search: api,
            tasks: widget.tasksApi,
            sections: widget.sectionsApi,
            labels: _labels,
            token: widget.token,
            projects: () => widget.projects.projects,
            rules: _matrixRules,
          ),
        ),
      ),
    );
  }

  void _openSearch(SearchApi api, {SavedFilter? filter}) {
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
            filters: _filters,
            initialFilter: filter,
            token: widget.token,
            projects: () => widget.projects.projects,
          ),
        ),
      ),
    );
  }

  Future<void> _newFilter() async {
    final filters = _filters;
    if (filters == null) return;
    final saved = await showFilterEditor(
      context,
      controller: filters,
      projectNames: [
        for (final p in widget.projects.projects)
          if (!p.isInbox) p.name,
      ],
      labelNames: [for (final l in _labels?.labels ?? const []) l.name],
    );
    if (saved != null && mounted && widget.tasksApi is SearchApi) {
      _openSearch(widget.tasksApi as SearchApi, filter: saved);
    }
  }

  Widget _sidebar() => ProjectSidebar(
    controller: widget.projects,
    selectedId: _section == 1 && _view == null && _labelId == null
        ? _selected?.id
        : null,
    labels: _labels,
    filters: _filters,
    onSelectFilter: switch (widget.tasksApi) {
      final SearchApi api => (filter) => _openSearch(api, filter: filter),
      _ => null,
    },
    onNewFilter: _filters == null ? null : _newFilter,
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
      onLogout: () => unawaited(_signOutFromHome()),
      startView: widget.startView,
      exportApi: widget.tasksApi is ExportApi
          ? widget.tasksApi as ExportApi
          : null,
      token: widget.token,
    ),
    // On a phone these are already in the bottom bar.
    tools: [
      SidebarRow(
        key: const ValueKey('tool-native-calendar'),
        selected: false,
        child: ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('تقویم'),
          onTap: _openNativeCalendar,
        ),
      ),
      // Secondary tools remain reachable from the compact mobile drawer.
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
      if (widget.habitReminders is LocalHabitReminders)
        SidebarRow(
          key: const ValueKey('tool-task-due-notifications'),
          selected: false,
          child: ListTile(
            leading: Icon(
              _taskDueNotificationsOn
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_outlined,
            ),
            title: const Text('اعلان سررسید کارها'),
            trailing: _taskDueNotificationsOn
                ? const Icon(Icons.check_circle_outline)
                : null,
            onTap: () => unawaited(_toggleTaskDueNotifications()),
          ),
        ),
      if (widget.tasksApi case final SearchApi api)
        SidebarRow(
          key: const ValueKey('tool-matrix'),
          selected: false,
          child: ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('ماتریس آیزنهاور'),
            onTap: () => _openMatrix(api),
          ),
        ),
    ],
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
                    showQuickCapture: false,
                    hideHeader: true,
                    doneToday: widget.tasksApi is ApiClient ? _doneToday : null,
                    focus: _focus,
                    onOpenFocus: () => _switchSection(2),
                    habits: _habits,
                    onOpenHabits: _habits == null
                        ? null
                        : () => _switchSection(4),
                  )
                : _section == 5
                ? TaskCalendarView(
                    key: const ValueKey('embedded-week-calendar'),
                    embedded: true,
                    loadTasks: _loadCalendarTasks,
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
                    onQuickAdd: _quickAdd,
                    embedded: true,
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
                      showQuickCapture: wide,
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
                    showQuickCapture: wide,
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
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  backgroundColor: Soft.ground(context),
                  surfaceTintColor: Colors.transparent,
                  toolbarHeight: 62,
                  titleSpacing: Space.gutter,
                  title: PressDepth(
                    child: InkWell(
                      key: const ValueKey('menval-wordmark'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(vertical: Space.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MenvalMark(size: 28),
                            const SizedBox(width: Space.sm),
                            Text(
                              'منوال',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    if (widget.tasksApi case final SearchApi api)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          end: Space.sm,
                        ),
                        child: PressDepth(
                          borderRadius: BorderRadius.circular(28),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              boxShadow: Soft.raised(context, depth: 2),
                            ),
                            child: IconButton(
                              key: const ValueKey('menval-header-search'),
                              tooltip: 'جست‌وجو',
                              onPressed: () => _openSearch(api),
                              icon: const Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                drawer: Drawer(
                  backgroundColor: Soft.ground(context),
                  child: _sidebar(),
                ),
                bottomNavigationBar: _approvedNav(),
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.startFloat,
                floatingActionButton: PressDepth(
                  borderRadius: BorderRadius.circular(18),
                  child: FloatingActionButton(
                    key: const ValueKey('menval-create-fab'),
                    shape: const CircleBorder(),
                    tooltip: _section == 4 ? 'عادت جدید' : 'کار جدید',
                    onPressed: _section == 4 ? _createHabitFromFab : _quickAdd,
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
                body: Row(
                  children: [
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
              bottomNavigationBar: _captureBar(),
              body: SafeArea(
                child: Row(
                  children: [
                    // The sidebar is one raised panel floating on the
                    // ground, like the page's tiles.
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        Space.md,
                        Space.md,
                        0,
                        Space.md,
                      ),
                      child: SizedBox(
                        width: 260,
                        child: Panel(
                          radius: 18,
                          child: ListenableBuilder(
                            listenable: _focus,
                            builder: (context, _) => _sidebar(),
                          ),
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
          const MenvalMark(size: 22),
          const SizedBox(width: Space.sm),
          Text(
            'منوال',
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
                  if (!HoverReveal.isTouch(context))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.sm),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.fromBorderSide(Soft.hairline(context)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'Ctrl K',
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ),
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
