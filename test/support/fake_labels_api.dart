import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/tasks/data/task.dart';

import 'fake_tasks_api.dart';

/// Labels in memory, behaving like the API: unique names per account,
/// favourites first, and a label's open tasks from the tasks fake.
class FakeLabelsApi implements LabelsApi {
  FakeLabelsApi({this.tasks});

  final FakeTasksApi? tasks;
  final _labels = <Label>[];
  var _nextId = 1;

  Label seed(String name, {String color = Label.defaultColor}) {
    final label = Label(id: 'l${_nextId++}', name: name, color: color);
    _labels.add(label);
    return label;
  }

  @override
  Future<List<Label>> listLabels(String token) async {
    final open = tasks == null ? const <Task>[] : await tasks!.allOpen();
    return [
      for (final l in [
        ..._labels,
      ]..sort((a, b) => (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0)))
        Label(
          id: l.id,
          name: l.name,
          color: l.color,
          isFavorite: l.isFavorite,
          openTaskCount: open.where((t) => t.labelIds.contains(l.id)).length,
        ),
    ];
  }

  @override
  Future<Label> createLabel(String token, LabelDraft draft) async {
    final name = draft.name!.trim().replaceFirst('@', '');
    if (_labels.any((l) => l.name.toLowerCase() == name.toLowerCase())) {
      throw const ApiException(
        'duplicate',
        statusCode: 409,
        code: 'duplicate_label',
      );
    }
    final label = Label(
      id: 'l${_nextId++}',
      name: name,
      color: draft.color ?? Label.defaultColor,
      isFavorite: draft.isFavorite ?? false,
    );
    _labels.add(label);
    return label;
  }

  @override
  Future<Label> updateLabel(String token, String id, LabelDraft changes) async {
    final i = _labels.indexWhere((l) => l.id == id);
    final l = _labels[i];
    final updated = Label(
      id: l.id,
      name: changes.name ?? l.name,
      color: changes.color ?? l.color,
      isFavorite: changes.isFavorite ?? l.isFavorite,
    );
    _labels[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteLabel(String token, String id) async {
    _labels.removeWhere((l) => l.id == id);
    tasks?.dropLabel(id);
  }

  @override
  Future<List<Task>> listLabelTasks(String token, String labelId) async => [
    for (final t in await tasks!.allOpen())
      if (t.labelIds.contains(labelId)) t,
  ];
}
