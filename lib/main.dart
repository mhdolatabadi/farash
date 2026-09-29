import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_configuration.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/app/backend_gate.dart';
import 'package:farash/core/api/api_client.dart';

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
        child: const _Placeholder(),
      ),
    );
  }
}

/// Stands in for the task screens until accounts and projects land.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فراش')),
      body: const Center(child: Text('به فراش خوش آمدید')),
    );
  }
}
