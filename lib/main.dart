import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_configuration.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/backend_gate.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/auth/auth_screen.dart';

void main() {
  runApp(const FarashApp());
}

class FarashApp extends StatefulWidget {
  const FarashApp({super.key, this.healthCheck});

  /// Test override; by default the app checks [AppConfiguration.apiBaseUri].
  final Future<void> Function()? healthCheck;

  @override
  State<FarashApp> createState() => _FarashAppState();
}

class _FarashAppState extends State<FarashApp> {
  late final ApiClient? _apiClient = AppConfiguration.apiBaseUri == null
      ? null
      : ApiClient(AppConfiguration.apiBaseUri!);

  AuthSession? _session;

  void _setSession(AuthSession session) {
    setState(() => _session = session);
  }

  void _signOut() {
    setState(() => _session = null);
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
        child: _apiClient == null
            ? const SizedBox.shrink()
            : _session == null
            ? AuthScreen(apiClient: _apiClient!, onAuthenticated: _setSession)
            : _HomeScreen(session: _session!, onSignOut: _signOut),
      ),
    );
  }
}

/// Stands in for the task screens until projects and tasks land.
class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.session, required this.onSignOut});

  final AuthSession session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فراش'),
        actions: [
          IconButton(
            tooltip: 'خروج',
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'سلام ${session.user.email}\nبه فراش خوش آمدید',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
