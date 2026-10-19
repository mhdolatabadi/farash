import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/tasks/data/task.dart';

abstract interface class TimeApi {
  Future<Map<String, dynamic>> timeRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

class TimeEntry {
  TimeEntry.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      taskId = j['task_id'] as String?,
      title = j['title'] as String,
      started = DateTime.parse(j['started_at'] as String),
      ended = j['ended_at'] == null
          ? null
          : DateTime.parse(j['ended_at'] as String),
      plannedEnd = j['planned_end'] == null
          ? null
          : DateTime.parse(j['planned_end'] as String),
      source = j['source'] as String;
  final String id, title, source;
  final String? taskId;
  final DateTime started;
  final DateTime? ended, plannedEnd;
  Duration elapsed(DateTime now) {
    var end = ended ?? now;
    if (plannedEnd != null && plannedEnd!.isBefore(end)) end = plannedEnd!;
    return end.isBefore(started) ? Duration.zero : end.difference(started);
  }
}

class TimeReport {
  TimeReport.fromJson(Map<String, dynamic> j)
    : active = j['active'] == null
          ? null
          : TimeEntry.fromJson(j['active'] as Map<String, dynamic>),
      entries = (j['entries'] as List)
          .map((e) => TimeEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      tasks = (j['tasks'] as List).cast<Map<String, dynamic>>(),
      seconds = j['seconds'] as int,
      today = j['today_seconds'] as int,
      now = DateTime.parse(j['server_now'] as String),
      truncated = j['truncated'] == true;
  final TimeEntry? active;
  final List<TimeEntry> entries;
  final List<Map<String, dynamic>> tasks;
  final int seconds, today;
  final DateTime now;
  final bool truncated;
}

String timeKey() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
String trackedTime(Duration d) {
  final seconds = d.inSeconds.clamp(0, 9999999999);
  return persianDigits(
    '${(seconds ~/ 3600).toString().padLeft(2, '0')}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
  );
}

class TimeTracker extends ChangeNotifier with WidgetsBindingObserver {
  TimeTracker({required this.api, required this.token}) {
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (++_ticks % 30 == 0) {
        unawaited(load());
      }
      if (_active != null) elapsedTicks.value++;
    });
    unawaited(load());
  }
  final TimeApi api;
  final String? Function() token;
  Timer? _tick;
  int _ticks = 0, _generation = 0;
  bool _disposed = false, busy = false;
  String? error;
  TimeReport? report;
  int revision = 0;
  final elapsedTicks = ValueNotifier<int>(0);
  final _clock = Stopwatch();
  DateTime? _anchor;
  DateTime get now => (_anchor ?? DateTime.now().toUtc()).add(_clock.elapsed);
  TimeEntry? _active;
  TimeEntry? get active => _active;
  Map<String, dynamic>? _lastMutation;
  ValueChanged<Task>? focusTask;
  String? _pendingStartKey, _pendingTask, _pendingSource;
  Future<TimeReport> fetch({String? taskId}) async {
    final current = token();
    if (current == null) throw StateError('signed out');
    final zone = await deviceTimeZone();
    final data = await api.timeRequest(
      current,
      'GET',
      '/api/v1/time?timezone=${Uri.encodeQueryComponent(zone)}${taskId == null ? '' : '&taskId=${Uri.encodeQueryComponent(taskId)}'}',
    );
    if (current != token()) throw StateError('account changed');
    return TimeReport.fromJson(data);
  }

  Future<void> load() async {
    final generation = ++_generation;
    try {
      final value = await fetch();
      if (_disposed || generation != _generation) return;
      report = value;
      _anchor = value.now;
      _active = value.active;
      if (!busy) error = null;
      revision++;
      _clock
        ..reset()
        ..start();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'زمان‌ها دریافت نشد؛ اتصال را بررسی و دوباره تلاش کنید.';
      }
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> mutate(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    if (busy || token() == null) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.timeRequest(token()!, method, path, body: body);
      _lastMutation = result;
      if (result['server_now'] is String) {
        _anchor = DateTime.parse(result['server_now'] as String);
        _clock
          ..reset()
          ..start();
      }
      if (result['id'] != null) {
        final entry = TimeEntry.fromJson(result);
        if (entry.ended == null) {
          _active = entry;
        } else if (_active?.id == entry.id) {
          _active = null;
        }
      } else if (method == 'DELETE' &&
          _active != null &&
          path.endsWith(_active!.id)) {
        _active = null;
      }
      await load();
      return true;
    } catch (_) {
      if (!_disposed) {
        error =
            'تغییر زمان ثبت نشد. ممکن است تایمر دیگری فعال باشد؛ وضعیت را تازه کنید.';
        await load();
      }
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> start(Task task, {int? focusSeconds}) async {
    // Reuse an idempotency key after a lost response, never award another interval.
    final source = focusSeconds == null ? 'timer' : 'focus';
    if (_pendingTask != task.id || _pendingSource != source) {
      _pendingStartKey = null;
      _pendingTask = task.id;
      _pendingSource = source;
    }
    _pendingStartKey ??= timeKey();
    final ok = await mutate(
      'POST',
      '/api/v1/time',
      body: {
        'task_id': task.id,
        'request_key': _pendingStartKey,
        'source': source,
        'focus_seconds': ?focusSeconds,
      },
    );
    if (ok) {
      _pendingStartKey = null;
      _pendingTask = null;
    }
    if (ok && _lastMutation?['ended_at'] != null) {
      error = 'جلسهٔ قبلی ثبت شده است؛ برای جلسهٔ تازه دوباره شروع کنید.';
      if (!_disposed) notifyListeners();
      return false;
    }
    return ok;
  }

  Future<bool> stop(TimeEntry entry) async {
    final ok = await mutate(
      'POST',
      '/api/v1/time/${Uri.encodeComponent(entry.id)}/stop',
    );
    if (ok) {
      _pendingStartKey = null;
      _pendingTask = null;
      _pendingSource = null;
    }
    return ok;
  }

  Future<bool> remove(TimeEntry entry) =>
      mutate('DELETE', '/api/v1/time/${Uri.encodeComponent(entry.id)}');
  Future<bool> save(
    Task task,
    DateTime start,
    DateTime end,
    String key, {
    TimeEntry? editing,
  }) => mutate(
    editing == null ? 'POST' : 'PATCH',
    editing == null
        ? '/api/v1/time'
        : '/api/v1/time/${Uri.encodeComponent(editing.id)}',
    body: {
      'task_id': task.id,
      'source': 'manual',
      'request_key': key,
      'started_at': start.toUtc().toIso8601String(),
      'ended_at': end.toUtc().toIso8601String(),
    },
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(load());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _tick?.cancel();
    _clock.stop();
    elapsedTicks.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class TrackerScope extends InheritedWidget {
  const TrackerScope({super.key, required this.tracker, required super.child});
  final TimeTracker? tracker;
  static TimeTracker? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackerScope>()?.tracker;
  @override
  bool updateShouldNotify(TrackerScope old) => old.tracker != tracker;
}
