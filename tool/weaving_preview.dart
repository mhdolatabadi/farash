// Offline fixture for native UI review only. Never a production entrypoint.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import '../test/support/fake_projects_api.dart';
import '../test/support/fake_tasks_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep semantics enabled for the CI UIAutomator interaction checks.
  SemanticsBinding.instance.ensureSemantics();
  final tasks = FakeTasksApi()..seed('inbox', 'مطالعهٔ فصل اول کتاب');
  final projects = ProjectsController(
    api: FakeProjectsApi(),
    token: () => 'preview',
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: FarashTheme.light(),
      darkTheme: FarashTheme.dark(),
      home: HomeScreen(
        email: 'preview@example.com',
        onLogout: () {},
        projects: projects,
        tasksApi: tasks,
        token: () => 'preview',
        startView: StartView(),
      ),
    ),
  );
}
