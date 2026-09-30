import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_configuration.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/backend_gate.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/application/auth_controller.dart';
import 'package:farash/features/auth/data/token_store.dart';
import 'package:farash/features/auth/presentation/auth_gate.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';

void main() {
  runApp(const FarashApp());
}

class FarashApp extends StatefulWidget {
  const FarashApp({
    super.key,
    this.healthCheck,
    this.authApi,
    this.tokenStore,
    this.projectsApi,
  });

  /// Test overrides; by default these talk to [AppConfiguration.apiBaseUri]
  /// and the device's secure storage.
  final Future<void> Function()? healthCheck;
  final AuthApi? authApi;
  final TokenStore? tokenStore;
  final ProjectsApi? projectsApi;

  @override
  State<FarashApp> createState() => _FarashAppState();
}

class _FarashAppState extends State<FarashApp> {
  late final ApiClient? _apiClient = AppConfiguration.apiBaseUri == null
      ? null
      : ApiClient(AppConfiguration.apiBaseUri!);
  late final AuthApi? _authApi = widget.authApi ?? _apiClient;
  late final AuthController? _auth = _authApi == null
      ? null
      : AuthController(
          api: _authApi,
          tokenStore: widget.tokenStore ?? SecureTokenStore(),
        );

  late final ProjectsApi? _projectsApi = widget.projectsApi ?? _apiClient;
  late final ProjectsController? _projects = _projectsApi == null
      ? null
      : ProjectsController(api: _projectsApi, token: () => _auth?.token);

  @override
  void dispose() {
    _auth?.dispose();
    _projects?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final projects = _projects;
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
        child: auth == null || projects == null
            ? const SizedBox.shrink()
            : AuthGate(
                controller: auth,
                signedIn: (context) => HomeScreen(
                  // A new account never sees the previous one's projects.
                  key: ValueKey(auth.user!.id),
                  email: auth.user!.email,
                  projects: projects,
                  onLogout: () {
                    projects.clear();
                    auth.logout();
                  },
                ),
              ),
      ),
    );
  }
}
