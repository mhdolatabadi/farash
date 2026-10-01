import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

void main() {
  test('health check calls /api/v1/health under the base path', () async {
    late Uri called;
    final client = ApiClient(
      Uri.parse('https://todo.example.com/farash/'),
      client: MockClient((request) async {
        called = request.url;
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    await client.checkHealth();

    expect(called.toString(), 'https://todo.example.com/farash/api/v1/health');
  });

  test('register decodes the returned auth session', () async {
    late Map<String, dynamic> body;
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/api/v1/auth/register');
        return http.Response(
          '{"token":"abc","user":{"id":"u1","email":"a@example.com"}}',
          201,
        );
      }),
    );

    final session = await client.register(
      email: 'a@example.com',
      password: 'long-enough',
    );

    expect(body['email'], 'a@example.com');
    expect(session.token, 'abc');
    expect(session.user.email, 'a@example.com');
  });

  test('login sends credentials and decodes the returned session', () async {
    late Uri called;
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        called = request.url;
        return http.Response(
          '{"token":"abc","user":{"id":"u1","email":"a@example.com"}}',
          200,
        );
      }),
    );

    final session = await client.login(
      email: 'a@example.com',
      password: 'long-enough',
    );

    expect(called.path, '/api/v1/auth/login');
    expect(session.user.id, 'u1');
  });

  test('me sends the bearer token', () async {
    late String? authorization;
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        authorization = request.headers['Authorization'];
        return http.Response(
          '{"user":{"id":"u1","email":"a@example.com"}}',
          200,
        );
      }),
    );

    final user = await client.me('token-123');

    expect(authorization, 'Bearer token-123');
    expect(user.email, 'a@example.com');
  });

  test('turns an error body into an ApiException with its code', () async {
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient(
        (_) async => http.Response('{"error":"database_unavailable"}', 503),
      ),
    );

    await expectLater(
      client.checkHealth(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.code, 'code', 'database_unavailable'),
      ),
    );
  });

  test('a network failure becomes an ApiException', () async {
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((_) async => throw http.ClientException('down')),
    );

    await expectLater(client.checkHealth(), throwsA(isA<ApiException>()));
  });

  test('task calls follow the tasks API contract', () async {
    final requests = <http.Request>[];
    const task = {
      'id': 't 1',
      'project_id': 'p1',
      'title': 'A',
      'description': '',
      'priority': 4,
      'sort_order': 0,
      'completed_at': null,
      'created_at': '2026-10-01T00:00:00Z',
      'updated_at': '2026-10-01T00:00:00Z',
    };
    final client = ApiClient(
      Uri.parse('https://todo.example.com'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'tasks': [task],
            }),
            200,
          );
        }
        if (request.method == 'DELETE' ||
            request.url.path.endsWith('reorder')) {
          return http.Response('', 204);
        }
        return http.Response(jsonEncode({'task': task}), 200);
      }),
    );

    final listed = await client.listTasks('tok', 'p1', showCompleted: true);
    await client.createTask(
      'tok',
      const TaskDraft(projectId: 'p1', title: 'A', priority: TaskPriority.p1),
    );
    await client.closeTask('tok', 't 1');
    await client.restoreTask('tok', 't 1');
    await client.deleteTask('tok', 't 1');
    await client.reorderTasks('tok', 'p1', ['t2', 't1']);

    expect(listed.single.id, 't 1');
    expect(requests[0].url.path, '/api/v1/tasks');
    expect(requests[0].url.queryParameters, {
      'projectId': 'p1',
      'showCompleted': 'true',
    });
    expect(requests[0].headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(requests[1].body), {
      'project_id': 'p1',
      'title': 'A',
      'priority': 1,
    });
    expect(requests[2].url.path, '/api/v1/tasks/t%201/close');
    expect(requests[3].url.path, '/api/v1/tasks/t%201/restore');
    expect(requests[4].method, 'DELETE');
    expect(jsonDecode(requests[5].body), {
      'project_id': 'p1',
      'task_ids': ['t2', 't1'],
    });
  });
}
