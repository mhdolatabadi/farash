import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/tasks/data/task.dart';

abstract interface class ScrumApi {
  Future<Map<String, dynamic>> agileRequest(
    String token,
    String method,
    String path, {
    Map<String, Object?>? body,
  });
}

class ScrumItem {
  ScrumItem.fromJson(Map<String, dynamic> j)
    : task = Task.fromJson(j['task'] as Map<String, dynamic>),
      kind = j['issue_type'] as String,
      points = j['points'] as int?,
      sprintId = j['sprint_id'] as String?,
      acceptance = j['acceptance'] as String,
      stage = j['stage'] as String;
  final Task task;
  final String kind, acceptance, stage;
  final int? points;
  final String? sprintId;
  String get column => task.isCompleted ? 'done' : stage;
  Map<String, Object?> fields({String? stage}) => {
    'issue_type': kind,
    'points': points,
    'sprint_id': sprintId,
    'acceptance': acceptance,
    'stage': stage ?? this.stage,
  };
}

class ScrumSprint {
  ScrumSprint(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  String get state => data['state'] as String;
  String get goal => data['goal'] as String;
  String get review => data['review'] as String;
  String get retro => data['retro'] as String;
  DateTime get start => DateTime.parse(data['starts_on'] as String);
  DateTime get end => DateTime.parse(data['ends_on'] as String);
  int? get capacity => data['capacity'] as int?;
  int number(String key) => data[key] as int? ?? 0;
}

class ScrumData {
  ScrumData.fromJson(Map<String, dynamic> j)
    : method = j['method'] as String,
      items = (j['items'] as List)
          .map((e) => ScrumItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      sprints = (j['sprints'] as List)
          .map((e) => ScrumSprint(e as Map<String, dynamic>))
          .toList(),
      events = (j['events'] as List).cast<Map<String, dynamic>>(),
      scope = (j['scope'] as List).cast<Map<String, dynamic>>();
  final String method;
  final List<ScrumItem> items;
  final List<ScrumSprint> sprints;
  final List<Map<String, dynamic>> events, scope;
  ScrumSprint? get active =>
      sprints.where((s) => s.state == 'active').firstOrNull;
}

class ScrumController extends ChangeNotifier {
  ScrumController({
    required this.api,
    required this.tasks,
    required this.token,
    required this.projectId,
  });
  final ScrumApi api;
  final TasksApi tasks;
  final String? Function() token;
  final String projectId;
  ScrumData? data;
  bool busy = false, disposed = false;
  int _generation = 0;
  String? error;
  String get base => '/api/v1/projects/${Uri.encodeComponent(projectId)}/agile';
  String get _token => token() ?? (throw StateError('signed out'));
  void publish() {
    if (!disposed) notifyListeners();
  }

  Future<void> load() async {
    final generation = ++_generation;
    final current = token();
    if (current == null) return;
    try {
      final value = await api.agileRequest(current, 'GET', base);
      if (disposed || generation != _generation || token() != current) return;
      data = ScrumData.fromJson(value);
      error = null;
    } catch (_) {
      if (!disposed && generation == _generation) {
        error = 'پروژه تازه نشد. اتصال را بررسی و دوباره تلاش کن.';
      }
    }
    publish();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (busy || disposed || token() == null) return false;
    busy = true;
    error = null;
    publish();
    try {
      await action();
      return true;
    } catch (e) {
      if (!disposed) {
        error = e is ApiException && e.code == 'agile_state_conflict'
            ? 'وضعیت پروژه تغییر کرده است. اسپرینت فعال را ببند؛ برآورد کار داخل اسپرینت فعال ثابت می‌ماند.'
            : 'ذخیره نشد. اتصال و وضعیت پروژه را بررسی و دوباره تلاش کن.';
      }
      return false;
    } finally {
      if (!disposed) {
        busy = false;
        publish();
      }
    }
  }

  Future<bool> write(String method, String suffix, Map<String, Object?> body) =>
      _run(() async {
        final current = _token;
        _generation++;
        final result = await api.agileRequest(
          current,
          method,
          '$base$suffix',
          body: body,
        );
        if (!disposed && token() == current) data = ScrumData.fromJson(result);
      });
  Future<bool> add(String title) => _run(() async {
    await tasks.createTask(
      _token,
      TaskDraft(projectId: projectId, title: title.trim()),
    );
    await load();
  });
  Future<bool> move(ScrumItem item, String column) => _run(() async {
    final current = _token;
    _generation++;
    if (column == 'done') {
      if (!item.task.isCompleted) await tasks.closeTask(current, item.task.id);
    } else {
      if (item.task.isCompleted) await tasks.reopenTask(current, item.task.id);
      await api.agileRequest(
        current,
        'PUT',
        '$base/items/${Uri.encodeComponent(item.task.id)}',
        body: item.fields(stage: column),
      );
    }
    await load();
  });
  @override
  void dispose() {
    disposed = true;
    _generation++;
    super.dispose();
  }
}

const scrumKinds = {
  'task': 'کار',
  'story': 'داستان',
  'bug': 'اشکال',
  'epic': 'اپیک',
};
const scrumColumns = {
  'todo': 'برای انجام',
  'doing': 'در جریان',
  'done': 'انجام‌شده',
};
const projectMethods = {
  'simple': 'ساده',
  'kanban': 'کانبان',
  'scrum': 'اسکرام',
};
