import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:menval/core/api/api_client.dart';
import 'package:menval/features/calendar/calendar_event.dart';

abstract interface class CalendarEventsApi {
  Future<Map<String, dynamic>> eventRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

/// A stable create intent prevents duplicate appointments after a lost reply.
class CalendarEventCreateAttempt {
  final requestKey =
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  String? _session;
  Map<String, Object?>? _payload;
  CalendarEvent? _confirmed;
}

class CalendarEventsController extends ChangeNotifier {
  CalendarEventsController({required this.api, required this.token});
  final CalendarEventsApi api;
  final String? Function() token;
  bool _disposed = false, saving = false;
  int _generation = 0;
  String? error;
  List<CalendarEvent> events = const [];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _call(
    String session,
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (_disposed || token() != session) throw const _EventSessionChanged();
    final result = await api.eventRequest(session, method, path, body: body);
    if (_disposed || token() != session) throw const _EventSessionChanged();
    return result;
  }

  Future<List<CalendarEvent>> load(DateTime from, DateTime to) async {
    final session = token(), generation = ++_generation;
    if (session == null) {
      events = const [];
      throw const _EventSessionChanged();
    }
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    try {
      final data = await _call(session, 'GET', '/api/v1/events?$query');
      if (_disposed || generation != _generation) return const [];
      events = [
        for (final e in data['events'] as List)
          CalendarEvent.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
      _notify();
      return events;
    } on _EventSessionChanged {
      events = const [];
      rethrow;
    }
  }

  String _message(Object failure) => switch (failure) {
    ApiException(code: 'calendar_event_conflict') =>
      'رویداد تغییر کرده است. فرم را ببندید، رویداد را دوباره باز کنید و تغییر را تکرار کنید.',
    ApiException(code: 'invalid_calendar_event') =>
      'عنوان، تاریخ یا زمان رویداد معتبر نیست.',
    ApiException(code: 'rate_limited') =>
      'درخواست‌ها زیاد شده‌اند. کمی بعد دوباره تلاش کنید.',
    _EventSessionChanged() =>
      'حساب تغییر کرده است. این صفحه را دوباره باز کنید.',
    _ => 'رویداد ذخیره نشد. اطلاعات فرم حفظ شده؛ دوباره تلاش کنید.',
  };

  Future<CalendarEvent?> save(
    CalendarEventDraft draft, {
    CalendarEvent? existing,
    required CalendarEventCreateAttempt attempt,
  }) async {
    if (saving || _disposed) return null;
    final session = token();
    if (session == null) return null;
    saving = true;
    error = null;
    _notify();
    try {
      final payload = draft.toJson();
      CalendarEvent event;
      if (existing != null) {
        final data = await _call(
          session,
          'PATCH',
          '/api/v1/events/${Uri.encodeComponent(existing.id)}',
          body: {...payload, 'version': existing.version},
        );
        event = CalendarEvent.fromJson(data['event'] as Map<String, dynamic>);
      } else {
        attempt._session ??= session;
        if (attempt._session != session) throw const _EventSessionChanged();
        attempt._payload ??= Map.unmodifiable(payload);
        var confirmed = attempt._confirmed;
        if (confirmed == null) {
          final data = await _call(
            session,
            'POST',
            '/api/v1/events',
            body: {...attempt._payload!, 'request_key': attempt.requestKey},
          );
          confirmed = CalendarEvent.fromJson(
            data['event'] as Map<String, dynamic>,
          );
          attempt._confirmed = confirmed;
        }
        if (jsonEncode(payload) != jsonEncode(attempt._payload)) {
          final data = await _call(
            session,
            'PATCH',
            '/api/v1/events/${Uri.encodeComponent(confirmed.id)}',
            body: {...payload, 'version': confirmed.version},
          );
          confirmed = CalendarEvent.fromJson(
            data['event'] as Map<String, dynamic>,
          );
          attempt._confirmed = confirmed;
          attempt._payload = Map.unmodifiable(payload);
        }
        event = confirmed;
      }
      events = [
        for (final e in events)
          if (e.id != event.id) e,
        event,
      ];
      return event;
    } catch (failure) {
      error = _message(failure);
      return null;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<bool> setDeleted(CalendarEvent event, bool deleted) async {
    if (saving || _disposed) return false;
    final session = token();
    if (session == null) return false;
    saving = true;
    error = null;
    _notify();
    try {
      final data = await _call(
        session,
        deleted ? 'DELETE' : 'POST',
        '/api/v1/events/${Uri.encodeComponent(event.id)}${deleted ? '' : '/restore'}',
      );
      events = [
        for (final e in events)
          if (e.id != event.id) e,
        if (!deleted)
          CalendarEvent.fromJson(data['event'] as Map<String, dynamic>),
      ];
      return true;
    } catch (failure) {
      error = _message(failure);
      return false;
    } finally {
      saving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

class _EventSessionChanged implements Exception {
  const _EventSessionChanged();
}
