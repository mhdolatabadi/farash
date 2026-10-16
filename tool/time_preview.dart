// Offline synthetic fixture for native time-tracking review only.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:farash/app/app_theme.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/features/home/home_screen.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/time_tracking/time_tracking.dart';
import '../test/support/fake_projects_api.dart';
import '../test/support/fake_tasks_api.dart';

class PreviewTimeApi extends FakeTasksApi implements TimeApi {
  Map<String, dynamic>? active;
  @override
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (method == 'POST') {
      if (path.endsWith('/stop')) {
        final old = {
          ...active!,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        };
        active = null;
        return old;
      }
      active = {
        'id': 'fixture-entry',
        'task_id': body!['task_id'],
        'title': 'مطالعهٔ فصل اول کتاب',
        'source': body['source'],
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'ended_at': null,
        'planned_end': null,
      };
      return active!;
    }
    final now = DateTime.now();
    final end = now.subtract(const Duration(hours: 1));
    final start = end.subtract(const Duration(hours: 1));
    final midnight = DateTime(now.year, now.month, now.day);
    final today = end.isBefore(midnight)
        ? 0
        : end.difference(start.isBefore(midnight) ? midnight : start).inSeconds;
    return {
      'active': active,
      'entries': [
        {
          'id': 'previous-entry',
          'task_id': 'task-1',
          'title': 'مطالعهٔ فصل اول کتاب',
          'source': 'manual',
          'started_at': start.toUtc().toIso8601String(),
          'ended_at': end.toUtc().toIso8601String(),
          'planned_end': null,
        },
      ],
      'tasks': [
        {
          'task_id': 'task-1',
          'title': 'مطالعهٔ فصل اول کتاب',
          'project': 'صندوق ورودی',
          'seconds': 3600,
        },
      ],
      'seconds': 3600,
      'today_seconds': today,
      'server_now': DateTime.now().toUtc().toIso8601String(),
      'truncated': false,
    };
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final api = PreviewTimeApi()..seed('inbox', 'مطالعهٔ فصل اول کتاب');
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
        tasksApi: api,
        token: () => 'preview',
        startView: StartView(),
      ),
    ),
  );
}
