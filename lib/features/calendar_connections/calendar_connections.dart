import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';

abstract interface class CalendarConnectionsApi {
  Future<Map<String, dynamic>> calendarRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

class CalendarConnection {
  const CalendarConnection(this.id, this.status);
  factory CalendarConnection.fromJson(Map<String, dynamic> json) =>
      CalendarConnection(json['id'] as String, json['status'] as String);
  final String id;
  final String status;
  bool get needsReconnect => status == 'reconnect_required';
}

class ConnectedCalendar {
  const ConnectedCalendar(this.id, this.title, this.timeZone, this.selected);
  factory ConnectedCalendar.fromJson(Map<String, dynamic> json) =>
      ConnectedCalendar(
        json['id'] as String,
        json['title'] as String? ?? 'تقویم بدون نام',
        json['time_zone'] as String? ?? '',
        json['selected'] == true,
      );
  final String id, title, timeZone;
  final bool selected;
}

class ConnectedEvent {
  ConnectedEvent.fromJson(Map<String, dynamic> json)
    : title = json['title'] as String? ?? 'رویداد خصوصی',
      calendarId = json['calendar_id'] as String,
      start = Map<String, dynamic>.from(json['start'] as Map),
      end = Map<String, dynamic>.from(json['end'] as Map);
  final String title, calendarId;
  final Map<String, dynamic> start, end;
  bool get allDay => start['date'] != null;
  DateTime get startsAt => allDay
      ? DateTime.parse(start['date'] as String)
      : DateTime.parse(start['dateTime'] as String).toLocal();
  DateTime get endsAt => allDay
      ? DateTime.parse(end['date'] as String)
      : DateTime.parse(end['dateTime'] as String).toLocal();
}

/// Private connection state belongs to the session which opened this screen.
/// Every awaited response is fenced; browser tickets never enter persistence.
class CalendarConnectionsController extends ChangeNotifier {
  CalendarConnectionsController({
    required this.api,
    required this.token,
    DateTime? now,
  }) : _session = token(),
       from = DateTime(
         (now ?? DateTime.now()).year,
         (now ?? DateTime.now()).month,
         (now ?? DateTime.now()).day,
       );

  final CalendarConnectionsApi api;
  final String? Function() token;
  final String? _session;
  bool _disposed = false;
  bool busy = false, loaded = false, configured = false;
  String? error, notice;
  CalendarConnection? connection;
  List<ConnectedCalendar> calendars = const [];
  List<ConnectedEvent> events = const [];
  Set<String> selection = {};
  int version = 0;
  Uri? authorization;
  DateTime from;
  DateTime get to => DateTime(from.year, from.month, from.day + 7);
  static const _base = '/api/v1/calendar-connections';
  String get _path => '$_base/${Uri.encodeComponent(connection!.id)}';
  bool get selectionChanged => !setEquals(
    selection,
    calendars.where((c) => c.selected).map((c) => c.id).toSet(),
  );

  bool _valid() {
    if (_disposed) return false;
    if (_session == null || token() != _session) {
      connection = null;
      calendars = const [];
      events = const [];
      selection = {};
      authorization = null;
      configured = false;
      error = 'حساب تغییر کرده است. این صفحه را ببندید و دوباره باز کنید.';
      return false;
    }
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (!_valid()) throw const _SessionChanged();
    final result = await api.calendarRequest(
      _session!,
      method,
      path,
      body: body,
    );
    if (!_valid()) throw const _SessionChanged();
    return result;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    if (!_valid()) {
      _notify();
      return;
    }
    busy = true;
    error = null;
    notice = null;
    _notify();
    try {
      await action();
    } on _SessionChanged {
      // _valid already cleared data and supplied the recovery message.
    } catch (failure) {
      if (_valid()) {
        final code = failure is ApiException ? failure.code : null;
        if (code == 'calendar_reconnect_required' && connection != null) {
          connection = CalendarConnection(connection!.id, 'reconnect_required');
          calendars = const [];
          events = const [];
          selection = {};
          authorization = null;
        }
        error = switch (code) {
          'calendar_reconnect_required' =>
            'دسترسی Google نیاز به تأیید دوباره دارد.',
          'calendar_state_conflict' =>
            'انتخاب تقویم‌ها تغییر کرده است. اطلاعات را بازخوانی و دوباره انتخاب کنید.',
          'rate_limited' =>
            'درخواست‌ها زیاد شده است. کمی بعد دوباره تلاش کنید.',
          _ => 'دریافت یا ذخیرهٔ اطلاعات تقویم انجام نشد. دوباره تلاش کنید.',
        };
      }
    } finally {
      if (!_disposed) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load() => _run(() async {
    authorization = null;
    final data = await _call('GET', _base);
    configured = data['configured'] == true;
    final rows = data['connections'] as List? ?? const [];
    connection = rows.isEmpty
        ? null
        : CalendarConnection.fromJson(
            Map<String, dynamic>.from(rows.first as Map),
          );
    calendars = const [];
    events = const [];
    selection = {};
    loaded = true;
    if (connection != null && !connection!.needsReconnect) await _details();
  });

  Future<void> _details() async {
    final data = await _call('GET', '$_path/calendars');
    final next = [
      for (final row in data['calendars'] as List)
        ConnectedCalendar.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    version = data['version'] as int;
    calendars = next;
    selection = next.where((c) => c.selected).map((c) => c.id).toSet();
    await _events();
  }

  Future<void> _events() async {
    events = const [];
    if (!calendars.any((calendar) => calendar.selected)) return;
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    final data = await _call('GET', '$_path/events?$query');
    events = [
      for (final row in data['events'] as List)
        ConnectedEvent.fromJson(Map<String, dynamic>.from(row as Map)),
    ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  }

  Future<void> prepareAuthorization(String client) => _run(() async {
    final data = await _call(
      'POST',
      '$_base/google/authorize',
      body: {'client': client, 'consent': true},
    );
    final uri = Uri.parse(data['start_url'] as String);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('Unsupported authorization address');
    }
    authorization = uri;
  });

  Uri? takeAuthorization() {
    if (!_valid() || busy) {
      _notify();
      return null;
    }
    final value = authorization;
    authorization = null;
    notice =
        'پس از تأیید در مرورگر، به برنامه برگردید و وضعیت اتصال را بررسی کنید.';
    _notify();
    return value;
  }

  void browserFailed() {
    if (!_valid()) return;
    error = 'مرورگر باز نشد. دوباره اتصال را آماده کنید.';
    _notify();
  }

  void select(String id, bool selected) {
    if (busy || !_valid() || !calendars.any((c) => c.id == id)) return;
    if (selected && selection.length >= 20) {
      error = 'حداکثر ۲۰ تقویم را انتخاب کنید.';
    } else {
      selection = {...selection};
      selected ? selection.add(id) : selection.remove(id);
      error = null;
    }
    _notify();
  }

  Future<void> saveSelection() => _run(() async {
    await _call(
      'PUT',
      '$_path/selection',
      body: {'calendar_ids': selection.toList(), 'version': version},
    );
    await _details();
    notice = 'انتخاب تقویم‌ها ذخیره شد.';
  });

  Future<void> moveWeek(int offset) => _run(() async {
    from = DateTime(from.year, from.month, from.day + offset * 7);
    await _events();
  });

  Future<void> disconnect() => _run(() async {
    final data = await _call('DELETE', _path);
    connection = null;
    calendars = const [];
    events = const [];
    selection = {};
    authorization = null;
    notice = data['revoked'] == true
        ? 'اتصال قطع شد و دسترسی Google لغو شد.'
        : 'اتصال در فراش قطع شد. برای اطمینان، دسترسی فراش را از حساب Google نیز لغو کنید.';
  });

  @override
  void dispose() {
    _disposed = true;
    authorization = null;
    super.dispose();
  }
}

class _SessionChanged implements Exception {
  const _SessionChanged();
}
