// Offline native review fixture; no account or production data.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/core/settings/theme_preferences.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';

import '../test/support/fake_projects_api.dart';
import '../test/support/fake_scrum_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final api = FakeScrumApi();
  final appearance = ThemePreferences();
  final projects = ProjectsController(
    api: FakeProjectsApi(
      projects: [
        const Project(
          id: 'inbox',
          name: 'صندوق ورودی',
          color: '#2563eb',
          isInbox: true,
        ),
        const Project(id: 'personal', name: 'پروژهٔ شخصی', color: '#98503D'),
      ],
    ),
    token: () => 'preview',
  );
  runApp(
    ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: FarashTheme.light(),
        darkTheme: FarashTheme.dark(),
        themeMode: appearance.mode,
        builder: (context, child) =>
            ThemePreferencesScope(preferences: appearance, child: child!),
        home: HomeScreen(
          email: 'preview@example.com',
          onLogout: () {},
          projects: projects,
          tasksApi: api,
          token: () => 'preview',
          startView: StartView(),
        ),
      ),
    ),
  );
}
