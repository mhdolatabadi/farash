import 'dart:async';
import 'dart:convert';

import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/offline/offline_read_cache.dart';
import 'package:farash/core/offline/offline_shell.dart';
import 'package:farash/core/settings/start_view.dart';
import 'package:farash/core/settings/theme_preferences.dart';
import 'package:farash/features/auth/data/auth_models.dart';
import 'package:farash/features/auth/session_store.dart';
import 'package:farash/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryOfflineStore implements OfflineCacheStore {
  String? raw;
  @override
  Future<String?> read() async => raw;
  @override
  Future<void> write(String value) async => raw = value;
  @override
  Future<void> clear() async => raw = null;
}

class DelayedOfflineStore extends MemoryOfflineStore {
  final started = Completer<void>();
  final result = Completer<String?>();
  @override
  Future<String?> read() {
    started.complete();
    return result.future;
  }
}

final _server = Uri.parse('https://example.test/farash');
const _identity = {
  'user': {'id': 'one', 'email': 'one@example.test'},
};

void main() {
  test(
    'cache persists bounded reads without plaintext token and expires',
    () async {
      final store = MemoryOfflineStore();
      var now = DateTime.utc(2026, 10, 22);
      final cache = OfflineReadCache(store: store, now: () => now);
      await cache.activate(_server, 'private-token');
      for (var i = 0; i < 25; i++) {
        await cache.remember(_server, 'private-token', cache.epoch, 'key$i', {
          'i': i,
        });
      }
      expect(cache.read(_server, 'private-token', cache.epoch, 'key0'), isNull);
      expect(cache.read(_server, 'private-token', cache.epoch, 'key24'), {
        'i': 24,
      });
      expect(
        utf8.encode(store.raw!).length,
        lessThanOrEqualTo(OfflineReadCache.maxBytes),
      );
      expect(store.raw, isNot(contains('private-token')));
      final restored = OfflineReadCache(store: store, now: () => now);
      await restored.activate(_server, 'private-token');
      expect(restored.read(_server, 'private-token', restored.epoch, 'key24'), {
        'i': 24,
      });
      now = now.add(const Duration(days: 8));
      expect(
        restored.read(_server, 'private-token', restored.epoch, 'key24'),
        isNull,
      );
    },
  );

  test(
    'server and token changes cannot read or resurrect an old session',
    () async {
      final store = MemoryOfflineStore();
      final cache = OfflineReadCache(store: store);
      await cache.activate(_server, 'first');
      final old = cache.epoch;
      await cache.remember(_server, 'first', old, 'me', _identity);
      await cache.activate(_server, 'second');
      await cache.remember(_server, 'first', old, 'me', _identity);
      expect(cache.read(_server, 'second', cache.epoch, 'me'), isNull);
      await cache.remember(_server, 'second', cache.epoch, 'me', _identity);
      expect(
        cache.read(
          Uri.parse('https://other.test'),
          'second',
          cache.epoch,
          'me',
        ),
        isNull,
      );
      await cache.clear();
      await cache.remember(_server, 'second', cache.epoch - 1, 'me', _identity);
      expect(store.raw, isNull);
    },
  );

  test(
    'oversized and corrupt persistent cache cannot become offline data',
    () async {
      final store = MemoryOfflineStore()..raw = '{broken';
      final cache = OfflineReadCache(store: store);
      await cache.activate(_server, 't');
      await cache.remember(_server, 't', cache.epoch, 'large', {
        'text': 'x' * OfflineReadCache.maxBytes,
      });
      expect(cache.read(_server, 't', cache.epoch, 'large'), isNull);
    },
  );

  test('logout supersedes a late persistent cache read', () async {
    final store = DelayedOfflineStore();
    final cache = OfflineReadCache(store: store);
    final opening = cache.activate(_server, 't');
    await store.started.future;
    await cache.clear();
    store.result.complete(
      jsonEncode({
        'scope': OfflineReadCache.scopeFor(_server, 't'),
        'entries': {
          'me': {
            'at': DateTime.now().toUtc().toIso8601String(),
            'body': _identity,
          },
        },
      }),
    );
    await opening;
    expect(cache.read(_server, 't', cache.epoch, 'me'), isNull);
    expect(store.raw, isNull);
  });

  test(
    'mutation invalidates lists and late reads but keeps identity',
    () async {
      final cache = OfflineReadCache(store: MemoryOfflineStore());
      await cache.activate(_server, 't');
      final generation = cache.epoch;
      final me = '$_server/api/v1/me';
      final tasks = '$_server/api/v1/tasks';
      await cache.remember(_server, 't', generation, me, _identity);
      await cache.remember(_server, 't', generation, tasks, {'tasks': []});
      // Corrupt persistent keys must not make a confirmed mutation fail.
      await cache.remember(_server, 't', generation, 'http://[invalid', {});
      await cache.invalidateData();
      await cache.remember(_server, 't', generation, tasks, {
        'tasks': ['late'],
      });
      expect(cache.read(_server, 't', cache.epoch, tasks), isNull);
      expect(cache.read(_server, 't', cache.epoch, me), _identity);
    },
  );

  test(
    'each concurrent mutation invalidates intervening cached reads',
    () async {
      final cache = OfflineReadCache(store: MemoryOfflineStore());
      await cache.activate(_server, 't');
      final firstStarted = Completer<void>();
      final secondStarted = Completer<void>();
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      var online = true;
      final api = ApiClient(
        _server,
        offlineCache: cache,
        client: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          if (request.method == 'DELETE') {
            if (request.url.path.endsWith('/first')) {
              firstStarted.complete();
              return firstResponse.future;
            }
            secondStarted.complete();
            return secondResponse.future;
          }
          return http.Response(
            jsonEncode({
              'projects': [
                {'id': 'second', 'name': 'Still present'},
              ],
            }),
            200,
          );
        }),
      );
      final first = api.deleteProject('t', 'first');
      final second = api.deleteProject('t', 'second');
      await Future.wait([firstStarted.future, secondStarted.future]);
      firstResponse.complete(http.Response('', 204));
      await first;
      expect((await api.listProjects('t')).single.id, 'second');
      final key = '$_server/api/v1/projects';
      expect(cache.read(_server, 't', cache.epoch, key), isNotNull);
      secondResponse.complete(http.Response('', 204));
      await second;
      expect(cache.read(_server, 't', cache.epoch, key), isNull);
      online = false;
      await expectLater(api.listProjects('t'), throwsA(isA<ApiException>()));
      expect(api.isOffline, isFalse);
    },
  );

  test('late mutation from another session preserves current cache', () async {
    final cache = OfflineReadCache(store: MemoryOfflineStore());
    await cache.activate(_server, 'old');
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = ApiClient(
      _server,
      offlineCache: cache,
      client: MockClient((_) async {
        started.complete();
        return response.future;
      }),
    );
    final pending = api.deleteProject('old', 'p');
    await started.future;
    await cache.clear();
    await cache.activate(_server, 'new');
    final key = '$_server/api/v1/projects';
    final body = {'projects': <Object>[]};
    await cache.remember(_server, 'new', cache.epoch, key, body);
    final currentGeneration = cache.epoch;
    response.complete(http.Response('', 204));
    await pending;
    expect(cache.epoch, currentGeneration);
    expect(cache.read(_server, 'new', cache.epoch, key), body);
  });

  test(
    'transport-only fallback blocks mutations until explicit reconnect',
    () async {
      final cache = OfflineReadCache(store: MemoryOfflineStore());
      await cache.activate(_server, 't');
      var online = true;
      var requests = 0;
      final api = ApiClient(
        _server,
        offlineCache: cache,
        client: MockClient((request) async {
          requests++;
          if (!online) throw http.ClientException('offline');
          return http.Response(
            request.url.path.endsWith('/me') ? jsonEncode(_identity) : '{}',
            200,
          );
        }),
      );
      expect((await api.me('t')).id, 'one');
      online = false;
      expect((await api.me('t')).id, 'one');
      expect(api.isOffline, isTrue);
      final before = requests;
      await expectLater(
        api.deleteProject('t', 'p'),
        throwsA(isA<ApiException>()),
      );
      expect(requests, before);
      online = true;
      await api.reconnect('t');
      expect(api.isOffline, isFalse);
      await api.deleteProject('t', 'p');
    },
  );

  test('HTTP errors never fall back and 401 wipes cached identity', () async {
    final store = MemoryOfflineStore();
    final cache = OfflineReadCache(store: store);
    var status = 200;
    final api = ApiClient(
      _server,
      offlineCache: cache,
      client: MockClient(
        (_) async => http.Response(jsonEncode(_identity), status),
      ),
    );
    await cache.activate(_server, 't');
    await api.me('t');
    for (final error in [404, 503, 401]) {
      status = error;
      await expectLater(
        api.me('t'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', error),
        ),
      );
      expect(api.isOffline, isFalse);
    }
    expect(store.raw, isNull);
  });

  test('a late old response cannot repopulate cache after logout', () async {
    final cache = OfflineReadCache(store: MemoryOfflineStore());
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiClient(
      _server,
      offlineCache: cache,
      client: MockClient((_) async {
        started.complete();
        return response.future;
      }),
    );
    await cache.activate(_server, 'old');
    final pending = api.me('old');
    await started.future;
    await api.clearOfflineSession();
    await cache.activate(_server, 'new');
    response.complete(http.Response(jsonEncode(_identity), 200));
    await pending;
    expect(await api.hasOfflineIdentity('new'), isFalse);
  });

  testWidgets('cached saved session opens app through offline health gate', (
    tester,
  ) async {
    final cache = OfflineReadCache(store: MemoryOfflineStore());
    final api = ApiClient(
      _server,
      offlineCache: cache,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await api.rememberAuthenticatedIdentity(
      const AuthSession(
        token: 't',
        user: AuthUser(id: 'one', email: 'one@example.test'),
      ),
    );
    for (final entry in <String, Object>{
      '/api/v1/projects': {
        'projects': [
          {'id': 'inbox', 'name': 'Inbox', 'is_inbox': true},
        ],
      },
      '/api/v1/tasks?projectId=inbox': {'tasks': []},
      '/api/v1/sections?projectId=inbox': {'sections': []},
      '/api/v1/labels': {'labels': []},
    }.entries) {
      await cache.remember(
        _server,
        't',
        cache.epoch,
        'https://example.test/farash${entry.key}',
        entry.value,
      );
    }
    await tester.pumpWidget(
      FarashApp(
        apiClient: api,
        sessionStore: MemorySessionStore('t'),
        calendarSettings: CalendarSettings(),
        startView: StartView(value: StartView.inbox),
        themePreferences: ThemePreferences(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('آفلاین؛ داده‌های ذخیره‌شده فقط برای مشاهده‌اند.'),
      findsOneWidget,
    );
    expect(find.text('اتصال به سرور برقرار نشد'), findsNothing);
    expect(find.byType(OfflineShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readonly banner wraps at 320px with doubled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cache = OfflineReadCache(store: MemoryOfflineStore())..usedOffline();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: OfflineShell(
          cache: cache,
          onReconnect: () async {},
          child: const Scaffold(body: Text('کارهای ذخیره‌شده')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('اتصال دوباره'), findsOneWidget);
    expect(find.text('کارهای ذخیره‌شده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
