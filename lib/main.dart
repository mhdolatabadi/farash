import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_configuration.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/backend_gate.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/widgets/app_loading_screen.dart';
import 'package:farash/features/auth/auth_screen.dart';
import 'package:farash/features/auth/data/auth_models.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';

void main() {
  runApp(const FarashApp());
}

class FarashApp extends StatefulWidget {
  const FarashApp({
    super.key,
    this.healthCheck,
    this.apiClient,
    this.sessionStore,
    this.projectsApi,
  });

  /// Test overrides; by default the app talks to
  /// [AppConfiguration.apiBaseUri] and the device's secure storage.
  final Future<void> Function()? healthCheck;
  final ApiClient? apiClient;
  final SessionStore? sessionStore;
  final ProjectsApi? projectsApi;

  @override
  State<FarashApp> createState() => _FarashAppState();
}

enum _SessionState { restoring, restoreFailed, ready }

class _FarashAppState extends State<FarashApp> {
  late final ApiClient? _apiClient =
      widget.apiClient ??
      (AppConfiguration.apiBaseUri == null
          ? null
          : ApiClient(AppConfiguration.apiBaseUri!));
  late final SessionStore _sessionStore =
      widget.sessionStore ?? SecureSessionStore();
  late final ProjectsApi? _projectsApi = widget.projectsApi ?? _apiClient;
  late final ProjectsController? _projects = _projectsApi == null
      ? null
      : ProjectsController(api: _projectsApi, token: () => _session?.token);

  AuthSession? _session;
  _SessionState _state = _SessionState.restoring;
  bool _restoreStarted = false;

  @override
  void dispose() {
    _projects?.dispose();
    super.dispose();
  }

  /// Restores the saved sign-in. A rejected token is dropped; a network
  /// failure keeps it so the user can retry without signing in again.
  Future<void> _restoreSession() async {
    final api = _apiClient;
    setState(() => _state = _SessionState.restoring);
    final token = await _sessionStore.readToken();
    if (api == null || token == null) {
      if (mounted) setState(() => _state = _SessionState.ready);
      return;
    }
    try {
      final user = await api.me(token);
      if (!mounted) return;
      setState(() {
        _session = AuthSession(token: token, user: user);
        _state = _SessionState.ready;
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) await _sessionStore.clear();
      if (!mounted) return;
      setState(() {
        _state = error.isUnauthorized
            ? _SessionState.ready
            : _SessionState.restoreFailed;
      });
    }
  }

  Future<void> _setSession(AuthSession session) async {
    await _sessionStore.writeToken(session.token);
    if (mounted) setState(() => _session = session);
  }

  Future<void> _signOut() async {
    // Never show one account's data to the next one.
    _projects?.clear();
    await _sessionStore.clear();
    if (mounted) setState(() => _session = null);
  }

  Widget _signedInOrAuth() {
    final api = _apiClient;
    final projects = _projects;
    if (api == null || projects == null) return const SizedBox.shrink();
    if (!_restoreStarted) {
      _restoreStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
    }
    final session = _session;
    return switch (_state) {
      _SessionState.restoring => const AppLoadingScreen(),
      _SessionState.restoreFailed => _RestoreFailedScreen(
        onRetry: _restoreSession,
      ),
      _SessionState.ready when session == null => AuthScreen(
        apiClient: api,
        onAuthenticated: _setSession,
      ),
      _SessionState.ready => HomeScreen(
        key: ValueKey(session!.user.id),
        email: session.user.email,
        projects: projects,
        onLogout: _signOut,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Farash',
      debugShowCheckedModeBanner: false,
      // Persian first: right-to-left layout and Persian Material strings
      // whatever the device language is. English comes with settings (#26).
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: FarashTheme.light(),
      darkTheme: FarashTheme.dark(),
      home: BackendGate(
        healthCheck: widget.healthCheck ?? _apiClient?.checkHealth,
        child: Builder(builder: (_) => _signedInOrAuth()),
      ),
    );
  }
}

class _RestoreFailedScreen extends StatelessWidget {
  const _RestoreFailedScreen({required this.onRetry});

  final VoidCallback onRetry;

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
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش دوباره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
