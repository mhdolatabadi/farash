import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:farash/features/auth/data/auth_models.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/tasks/data/task.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// Machine-readable error from the API body, for example `email_taken`.
  final String? code;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

abstract interface class AuthApi {
  Future<AuthSession> register({
    required String email,
    required String password,
  });
  Future<AuthSession> login({required String email, required String password});
  Future<AuthUser> me(String token);
}

/// Fields for a new project, or the fields to change on an existing one.
class ProjectDraft {
  const ProjectDraft({
    this.name,
    this.color,
    this.parentId,
    this.moveParent = false,
    this.isFavorite,
    this.isArchived,
    this.sortOrder,
    this.kind,
  });

  final String? name;
  final String? color;
  final String? parentId;

  /// On update: move under [parentId], or to the top level when it is null.
  final bool moveParent;
  final bool? isFavorite;
  final bool? isArchived;
  final int? sortOrder;
  final ProjectKind? kind;

  Map<String, Object?> toJson() => {
    'name': ?name,
    'color': ?color,
    // The API reads an empty parent_id as "move to the top level".
    if (moveParent || parentId != null) 'parent_id': parentId ?? '',
    'is_favorite': ?isFavorite,
    'is_archived': ?isArchived,
    'sort_order': ?sortOrder,
    if (kind != null) 'kind': kind!.name,
  };
}

abstract interface class ProjectsApi {
  /// Every project of the account, archived ones included.
  Future<List<Project>> listProjects(String token);
  Future<Project> createProject(String token, ProjectDraft draft);
  Future<Project> updateProject(String token, String id, ProjectDraft changes);
  Future<void> deleteProject(String token, String id);
}

/// Fields for a new task, or the fields to change on an existing one.
class TaskDraft {
  const TaskDraft({
    this.projectId,
    this.title,
    this.description,
    this.priority,
    this.sortOrder,
  });

  final String? projectId;
  final String? title;

  /// An empty string clears the description.
  final String? description;
  final TaskPriority? priority;
  final int? sortOrder;

  Map<String, Object?> toJson() => {
    'project_id': ?projectId,
    'title': ?title,
    'description': ?description,
    if (priority != null) 'priority': priority!.level,
    'sort_order': ?sortOrder,
  };
}

abstract interface class TasksApi {
  /// The project's tasks in order; completed ones only when asked.
  Future<List<Task>> listTasks(
    String token,
    String projectId, {
    bool showCompleted = false,
  });
  Future<Task> createTask(String token, TaskDraft draft);
  Future<Task> updateTask(String token, String id, TaskDraft changes);
  Future<Task> closeTask(String token, String id);
  Future<Task> reopenTask(String token, String id);

  /// Soft-deletes the task; [restoreTask] brings it back.
  Future<void> deleteTask(String token, String id);
  Future<Task> restoreTask(String token, String id);
  Future<void> reorderTasks(String token, String projectId, List<String> ids);
}

/// Talks to the Farash API. Feature interfaces are implemented here so that
/// one HTTP client serves the whole app.
class ApiClient implements AuthApi, ProjectsApi, TasksApi {
  ApiClient(this.baseUri, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUri;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<void> checkHealth() async {
    await _send('GET', '/api/v1/health');
  }

  @override
  Future<List<Project>> listProjects(String token) async {
    final body =
        await _send('GET', '/api/v1/projects', token: token)
            as Map<String, dynamic>;
    return [
      for (final item in body['projects'] as List<dynamic>)
        Project.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Project> createProject(String token, ProjectDraft draft) async =>
      _project(
        await _send(
          'POST',
          '/api/v1/projects',
          token: token,
          body: draft.toJson(),
        ),
      );

  @override
  Future<Project> updateProject(
    String token,
    String id,
    ProjectDraft changes,
  ) async => _project(
    await _send(
      'PATCH',
      '/api/v1/projects/${Uri.encodeComponent(id)}',
      token: token,
      body: changes.toJson(),
    ),
  );

  @override
  Future<void> deleteProject(String token, String id) async {
    await _send(
      'DELETE',
      '/api/v1/projects/${Uri.encodeComponent(id)}',
      token: token,
    );
  }

  static Project _project(Object? body) => Project.fromJson(
    (body as Map<String, dynamic>)['project'] as Map<String, dynamic>,
  );

  @override
  Future<List<Task>> listTasks(
    String token,
    String projectId, {
    bool showCompleted = false,
  }) async {
    final body =
        await _send(
              'GET',
              '/api/v1/tasks',
              token: token,
              query: {
                'projectId': projectId,
                if (showCompleted) 'showCompleted': 'true',
              },
            )
            as Map<String, dynamic>;
    return [
      for (final item in body['tasks'] as List<dynamic>)
        Task.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Task> createTask(String token, TaskDraft draft) async => _task(
    await _send('POST', '/api/v1/tasks', token: token, body: draft.toJson()),
  );

  @override
  Future<Task> updateTask(String token, String id, TaskDraft changes) async =>
      _task(
        await _send(
          'PATCH',
          _taskPath(id),
          token: token,
          body: changes.toJson(),
        ),
      );

  @override
  Future<Task> closeTask(String token, String id) async =>
      _task(await _send('POST', '${_taskPath(id)}/close', token: token));

  @override
  Future<Task> reopenTask(String token, String id) async =>
      _task(await _send('POST', '${_taskPath(id)}/reopen', token: token));

  @override
  Future<void> deleteTask(String token, String id) async {
    await _send('DELETE', _taskPath(id), token: token);
  }

  @override
  Future<Task> restoreTask(String token, String id) async =>
      _task(await _send('POST', '${_taskPath(id)}/restore', token: token));

  @override
  Future<void> reorderTasks(
    String token,
    String projectId,
    List<String> ids,
  ) async {
    await _send(
      'POST',
      '/api/v1/tasks/reorder',
      token: token,
      body: {'project_id': projectId, 'task_ids': ids},
    );
  }

  static String _taskPath(String id) =>
      '/api/v1/tasks/${Uri.encodeComponent(id)}';

  static Task _task(Object? body) => Task.fromJson(
    (body as Map<String, dynamic>)['task'] as Map<String, dynamic>,
  );

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) async {
    final decoded = await _send(
      'POST',
      '/api/v1/auth/register',
      body: {'email': email, 'password': password},
    );
    return AuthSession.fromJson(decoded as Map<String, dynamic>);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final decoded = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'email': email, 'password': password},
    );
    return AuthSession.fromJson(decoded as Map<String, dynamic>);
  }

  @override
  Future<AuthUser> me(String token) async {
    final decoded = await _send('GET', '/api/v1/me', token: token);
    final json = decoded as Map<String, dynamic>;
    return AuthUser.fromJson(json['user'] as Map<String, dynamic>);
  }

  Uri _uri(String path, [Map<String, String>? query]) => baseUri.replace(
    path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  /// Sends a request and returns the decoded JSON body (null when empty).
  Future<Object?> _send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on Exception {
      throw const ApiException('اتصال به سرور برقرار نشد.');
    }

    final decoded = response.body.isEmpty
        ? null
        : _tryDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final code = decoded is Map<String, dynamic>
        ? decoded['error'] as String?
        : null;
    throw ApiException(
      _messageFor(response.statusCode, code),
      statusCode: response.statusCode,
      code: code,
    );
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  static String _messageFor(int status, String? code) {
    if (code == 'email_taken') return 'این ایمیل قبلا ثبت شده است.';
    if (code == 'invalid_credentials') return 'ایمیل یا رمز عبور درست نیست.';
    if (code == 'invalid_email') return 'ایمیل را درست وارد کنید.';
    if (code == 'invalid_password') {
      return 'رمز عبور باید بین ۸ تا ۷۲ کاراکتر باشد.';
    }
    if (status == 401) return 'نشست شما منقضی شده است. دوباره وارد شوید.';
    if (status == 404) return 'پیدا نشد.';
    if (status == 429) {
      return 'درخواست‌ها زیاد است. کمی بعد دوباره امتحان کنید.';
    }
    if (status >= 500) return 'خطای سرور. کمی بعد دوباره امتحان کنید.';
    return 'درخواست انجام نشد.';
  }
}
