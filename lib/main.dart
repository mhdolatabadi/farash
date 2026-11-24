import 'package:menval/core/offline/offline_read_cache.dart';
import 'package:menval/core/offline/offline_shell.dart';
import 'package:flutter/material.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:menval/core/settings/theme_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:menval/core/calendar/calendar_scope.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/app/app_configuration.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/app/backend_gate.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/core/widgets/app_loading_screen.dart';
import 'package:menval/features/auth/auth_screen.dart';
import 'package:menval/features/auth/data/auth_models.dart';
import 'package:menval/features/auth/session_store.dart';
import 'package:menval/features/habits/reminders/habit_reminders.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/projects/application/projects_controller.dart';

void main() {
  runApp(const MenvalApp());
}

class MenvalApp extends StatefulWidget {
  const MenvalApp({
    super.key,
    this.healthCheck,
    this.apiClient,
    this.sessionStore,
    this.refreshCredentialStore,
    this.projectsApi,
    this.tasksApi,
    this.sectionsApi,
    this.calendarSettings,
    this.startView,
    this.labelsApi,
    this.themePreferences,
    this.habitReminders,
  });

  /// Test overrides; by default the app talks to
  /// [AppConfiguration.apiBaseUri] and the device's secure storage.
  final Future<void> Function()? healthCheck;
  final ApiClient? apiClient;
  final SessionStore? sessionStore;
  final RefreshCredentialStore? refreshCredentialStore;
  final ProjectsApi? projectsApi;
  final TasksApi? tasksApi;
  final SectionsApi? sectionsApi;
  final CalendarSettings? calendarSettings;

  /// Which list opens first; per device.
  final StartView? startView;
  final LabelsApi? labelsApi;
  final ThemePreferences? themePreferences;

  /// Null in tests unless one is given; the platform's otherwise.
  final HabitReminders? habitReminders;

  @override
  State<MenvalApp> createState() => _MenvalAppState();
}

enum _SessionState { restoring, restoreFailed, ready }

class _MenvalAppState extends State<MenvalApp> {
  late final ApiClient? _apiClient =
      widget.apiClient ??
      (AppConfiguration.apiBaseUri == null
          ? null
          : ApiClient(
              AppConfiguration.apiBaseUri!,
              offlineCache: OfflineReadCache(),
            ));
  late final SessionStore _sessionStore =
      widget.sessionStore ?? SecureSessionStore();
  late final RefreshCredentialStore _refreshStore =
      widget.refreshCredentialStore ??
      (widget.sessionStore == null
          ? SecureRefreshCredentialStore()
          : MemoryRefreshCredentialStore());
  late final ProjectsApi? _projectsApi = widget.projectsApi ?? _apiClient;
  late final ProjectsController? _projects = _projectsApi == null
      ? null
      : ProjectsController(api: _projectsApi, token: () => _session?.token);

  late final TasksApi? _tasksApi = widget.tasksApi ?? _apiClient;
  late final SectionsApi? _sectionsApi = widget.sectionsApi ?? _apiClient;
  late final CalendarSettings _calendar =
      widget.calendarSettings ??
      (CalendarSettings(store: SecureCalendarSettingsStore())..load());
  late final StartView _startView =
      widget.startView ??
      (StartView(store: SecureCalendarSettingsStore())..load());

  /// Tests that bring their own API get no platform reminders.
  late final HabitReminders? _reminders =
      widget.habitReminders ??
      (widget.apiClient == null && widget.tasksApi == null
          ? HabitReminders.forPlatform()
          : null);

  late final ThemePreferences _appearance =
      widget.themePreferences ??
      (ThemePreferences(store: SecureCalendarSettingsStore())..load());

  AuthSession? _session;
  _SessionState _state = _SessionState.restoring;
  bool _restoreStarted = false;
  int _sessionEpoch = 0;

  @override
  void dispose() {
    _projects?.dispose();
    if (widget.themePreferences == null) _appearance.dispose();
    if (widget.habitReminders == null) _reminders?.dispose();
    super.dispose();
  }

  /// Restore an existing account without throwing away credentials after a
  /// transient network error or a stale single-use refresh token. An old
  /// access token may still be valid after a competing browser tab rotates
  /// the refresh credential.
  Future<void> _restoreSession() async {
    final generation = ++_sessionEpoch;
    final api = _apiClient;
    setState(() => _state = _SessionState.restoring);
    try {
      final token = await _sessionStore.readToken();
      final refresh = await _refreshStore.readRefreshToken();
      if (!mounted || generation != _sessionEpoch) return;
      if (api == null || (token == null && refresh == null)) {
        setState(() => _state = _SessionState.ready);
        return;
      }

      AuthSession session;
      if (refresh != null) {
        try {
          // Refresh first so an expired access token can recover.
          session = await api.refreshSession(refresh);
        } on ApiException {
          // A second browser tab may already have rotated both credentials
          // in shared secure storage. Re-read the access token after the
          // failure rather than retrying a stale token from this widget.
          final latestAccess = await _sessionStore.readToken();
          final fallbackAccess = latestAccess ?? token;
          if (fallbackAccess == null) rethrow;
          // The server must verify this access token, or the existing
          // account-scoped offline cache must have its saved identity.
          await api.activateOfflineSession(fallbackAccess);
          final user = await api.me(fallbackAccess);
          session = AuthSession(token: fallbackAccess, user: user);
          // Do not clear the refresh store: another tab may have written
          // the newly rotated credential while this request was in flight.
        }
      } else {
        await api.activateOfflineSession(token!);
        final user = await api.me(token);
        session = AuthSession(token: token, user: user);
      }
      if (!mounted || generation != _sessionEpoch) return;

      if (session.refreshToken != null) {
        await _refreshStore.writeRefreshToken(session.refreshToken!);
        await _sessionStore.writeToken(session.token);
      }
      if (!mounted || generation != _sessionEpoch) return;
      await api.rememberAuthenticatedIdentity(session);
      if (!mounted || generation != _sessionEpoch) return;
      setState(() {
        _session = session;
        _state = _SessionState.ready;
      });
    } on ApiException {
      if (!mounted || generation != _sessionEpoch) return;
      setState(() => _state = _SessionState.restoreFailed);
    } on Exception {
      if (!mounted || generation != _sessionEpoch) return;
      setState(() => _state = _SessionState.restoreFailed);
    }
  }

  void _showLoginInsteadOfRetry() {
    ++_sessionEpoch;
    // Never erase saved credentials or offline data on this action. Logging
    // in successfully will overwrite the stale tokens with a valid session.
    setState(() {
      _session = null;
      _state = _SessionState.ready;
    });
  }

  Future<void> _setSession(AuthSession session) async {
    ++_sessionEpoch;
    await _apiClient?.rememberAuthenticatedIdentity(session);
    await _sessionStore.writeToken(session.token);
    if (session.refreshToken != null) {
      await _refreshStore.writeRefreshToken(session.refreshToken!);
    }
    if (mounted) setState(() => _session = session);
  }

  Future<void> _signOut() async {
    ++_sessionEpoch;
    await _apiClient?.clearOfflineSession();
    // Never show one account's data to the next one.
    _projects?.clear();
    final refresh = await _refreshStore.readRefreshToken();
    // Local revocation takes priority over a failed network request.
    await _refreshStore.clearRefreshToken();
    await _sessionStore.clear();
    if (refresh != null) {
      try {
        await _apiClient?.revokeSession(refresh);
      } on ApiException {
        // The server will still expire an unreachable refresh session.
      }
    }
    await _reminders?.clear();
    if (mounted) setState(() => _session = null);
  }

  Future<void> _checkBackend() async {
    final check = widget.healthCheck ?? _apiClient?.checkHealth;
    if (check == null) return;
    try {
      await check();
    } on ApiException catch (error) {
      final api = _apiClient;
      if (error.statusCode != null || api == null) rethrow;
      final token = await _sessionStore.readToken();
      if (token == null) rethrow;
      await api.activateOfflineSession(token);
      if (!await api.hasOfflineIdentity(token)) rethrow;
      api.offlineCache?.usedOffline();
    }
  }

  Future<void> _reconnect() async {
    final api = _apiClient;
    final session = _session;
    if (api == null || session == null) return;
    try {
      await api.reconnect(session.token);
      await _projects?.load();
    } on ApiException catch (error) {
      if (error.isUnauthorized) await _signOut();
      rethrow;
    }
  }

  Widget _offlineShell(Widget child) {
    final cache = _apiClient?.offlineCache;
    return cache == null
        ? child
        : OfflineShell(cache: cache, onReconnect: _reconnect, child: child);
  }

  Widget _signedInOrAuth() {
    final api = _apiClient;
    final projects = _projects;
    final tasks = _tasksApi;
    if (api == null || projects == null || tasks == null) {
      return const SizedBox.shrink();
    }
    if (!_restoreStarted) {
      _restoreStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
    }
    final session = _session;
    return switch (_state) {
      _SessionState.restoring => const AppLoadingScreen(),
      _SessionState.restoreFailed => _RestoreFailedScreen(
        onRetry: _restoreSession,
        onLogin: _showLoginInsteadOfRetry,
      ),
      _SessionState.ready when session == null => AuthScreen(
        apiClient: api,
        onAuthenticated: _setSession,
      ),
      _SessionState.ready => _offlineShell(
        HomeScreen(
          key: ValueKey(session!.user.id),
          email: session.user.email,
          projects: projects,
          tasksApi: tasks,
          sectionsApi: _sectionsApi,
          token: () => _session?.token,
          onLogout: _signOut,
          startView: _startView,
          labelsApi: widget.labelsApi ?? _apiClient,
          habitReminders: _reminders,
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _appearance,
    builder: (context, _) => _buildApp(),
  );

  Widget _buildApp() {
    return MaterialApp(
      title: 'Menval',
      builder: (context, child) => ThemePreferencesScope(
        preferences: _appearance,
        child: CalendarScope(settings: _calendar, child: child!),
      ),
      debugShowCheckedModeBanner: false,
      // Persian first: right-to-left layout and Persian Material strings
      // whatever the device language is. English comes with settings (#26).
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: _appearance.mode,
      theme: MenvalTheme.light(),
      darkTheme: MenvalTheme.dark(),
      home: BackendGate(
        healthCheck: widget.healthCheck != null || _apiClient != null
            ? _checkBackend
            : null,
        child: Builder(builder: (_) => _signedInOrAuth()),
      ),
    );
  }
}

class _RestoreFailedScreen extends StatelessWidget {
  const _RestoreFailedScreen({required this.onRetry, required this.onLogin});

  final VoidCallback onRetry;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('بازیابی ورود قبلی ممکن نشد'),
              const SizedBox(height: 12),
              const Text(
                'ممکن است نشست قبلی منقضی شده یا ارتباط با سرور قطع شده باشد. '
                'می‌توانید دوباره تلاش کنید یا بدون پاک‌کردن اطلاعات مرورگر وارد حساب خود شوید.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onLogin,
                child: const Text('ورود دوباره به حساب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
