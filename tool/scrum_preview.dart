// Offline native review fixture; no account or production data.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:menval/app/app_theme.dart';
import 'package:menval/core/settings/start_view.dart';
import 'package:menval/core/settings/theme_preferences.dart';
import 'package:menval/features/home/home_screen.dart';
import 'package:menval/features/calendar_connections/calendar_connections.dart';
import 'package:menval/features/projects/application/projects_controller.dart';
import 'package:menval/features/projects/data/project.dart';

import '../test/support/fake_projects_api.dart';
import '../test/support/fake_scrum_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final api = _CalendarPreviewApi();
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
        theme: MenvalTheme.light(),
        darkTheme: MenvalTheme.dark(),
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

// Synthetic Google-shaped data only; the fixture never starts real consent.
class _CalendarPreviewApi extends FakeScrumApi
    implements CalendarConnectionsApi {
  @override
  Future<Map<String, dynamic>> calendarRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (path.endsWith('/calendars')) {
      return {
        'version': 1,
        'calendars': [
          {
            'id': 'preview-calendar',
            'title': 'مطالعه و جلسه‌ها',
            'time_zone': 'Asia/Tehran',
            'selected': true,
          },
        ],
      };
    }
    if (Uri.parse(path).path.endsWith('/events')) {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final tomorrow = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      return {
        'complete': true,
        'events': [
          {
            'id': 'preview-event',
            'calendar_id': 'preview-calendar',
            'title': 'جلسهٔ مطالعه',
            'start': {'date': day},
            'end': {'date': tomorrow},
            'read_only': true,
          },
        ],
      };
    }
    return {
      'configured': true,
      'connections': [
        {
          'id': 'preview-connection',
          'provider': 'google',
          'status': 'connected',
          'version': 1,
        },
      ],
    };
  }
}
