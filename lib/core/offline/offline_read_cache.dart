import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class OfflineCacheStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureOfflineCacheStore implements OfflineCacheStore {
  SecureOfflineCacheStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'farash.offline_reads.v1';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// A bounded convenience snapshot, never a write queue or authoritative database.
/// The scope includes the complete server address and a hash of the exact token.
class OfflineReadCache extends ChangeNotifier {
  OfflineReadCache({OfflineCacheStore? store, DateTime Function()? now})
    : _store = store ?? SecureOfflineCacheStore(),
      _now = now ?? DateTime.now;

  static const maxBytes = 1024 * 1024;
  static const maxResponses = 20;
  static const maxAge = Duration(days: 7);
  final OfflineCacheStore _store;
  final DateTime Function() _now;
  Map<String, dynamic> _entries = {};
  String? _scope;
  int _epoch = 0;
  bool _offline = false;
  Future<void> _writes = Future<void>.value();

  bool get isOffline => _offline;
  int get epoch => _epoch;

  static String scopeFor(Uri server, String token) =>
      sha256.convert(utf8.encode('${server.toString()}\n$token')).toString();

  bool matches(Uri server, String? token, int generation) =>
      token != null &&
      generation == _epoch &&
      _scope == scopeFor(server, token);

  static bool allows(String path) => const {
    '/api/v1/me',
    '/api/v1/projects',
    '/api/v1/tasks',
    '/api/v1/sections',
    '/api/v1/labels',
  }.contains(path);

  Future<void> activate(Uri server, String token) async {
    final next = scopeFor(server, token);
    if (_scope == next) return;
    _scope = next;
    final generation = ++_epoch;
    _entries = {};
    _setOffline(false);
    try {
      // Finish any pending old-scope persistence before reading a new scope.
      await _writes;
      final raw = await _store.read();
      if (generation != _epoch || raw == null) return;
      if (utf8.encode(raw).length > maxBytes) {
        await _persist();
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['scope'] == next &&
          decoded['entries'] is Map<String, dynamic>) {
        final entries = Map<String, dynamic>.from(decoded['entries'] as Map);
        if (entries.length <= maxResponses) _entries = entries;
      }
      _prune();
      await _persist();
    } catch (_) {
      // Storage failure cannot turn a failed server request into confirmed data.
    }
  }

  Object? read(Uri server, String? token, int generation, String key) {
    if (!matches(server, token, generation)) return null;
    _prune();
    final entry = _entries[key];
    return entry is Map<String, dynamic> ? entry['body'] : null;
  }

  Future<void> remember(
    Uri server,
    String? token,
    int generation,
    String key,
    Object? body,
  ) async {
    if (!matches(server, token, generation) || body == null) return;
    final copied = jsonDecode(jsonEncode(body));
    final entry = {'at': _now().toUtc().toIso8601String(), 'body': copied};
    if (utf8.encode(jsonEncode(entry)).length > maxBytes ~/ 2) return;
    _prune();
    _entries.remove(key);
    _entries[key] = entry;
    while (_entries.length > maxResponses ||
        utf8.encode(_encode()).length > maxBytes) {
      _entries.remove(_entries.keys.first);
    }
    await _persist();
  }

  void usedOffline() => _setOffline(true);
  void reconnected() => _setOffline(false);

  Future<void> clear() async {
    ++_epoch;
    _scope = null;
    _entries = {};
    _setOffline(false);
    _writes = _writes.then((_) => _store.clear()).catchError((_) {});
    await _writes;
  }

  Future<void> invalidateData() async {
    ++_epoch;
    _entries.removeWhere(
      (key, _) => !(Uri.tryParse(key)?.path.endsWith('/api/v1/me') ?? false),
    );
    await _persist();
  }

  void _prune() {
    _entries.removeWhere((_, value) {
      if (value is! Map<String, dynamic>) return true;
      final raw = value['at'];
      final at = raw is String ? DateTime.tryParse(raw) : null;
      if (at == null) return true;
      final age = _now().toUtc().difference(at);
      return age.isNegative || age > maxAge;
    });
  }

  String _encode() => jsonEncode({'scope': _scope, 'entries': _entries});
  Future<void> _persist() {
    final raw = _encode();
    _writes = _writes.then((_) => _store.write(raw)).catchError((_) {});
    return _writes;
  }

  void _setOffline(bool value) {
    if (value == _offline) return;
    _offline = value;
    notifyListeners();
  }
}
