import 'package:flutter/foundation.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/features/labels/data/label.dart';

/// The signed-in account's labels.
class LabelsController extends ChangeNotifier {
  LabelsController({required LabelsApi api, required this.token}) : _api = api;

  final LabelsApi _api;

  /// The current access token; null once signed out.
  final String? Function() token;

  List<Label> _labels = const [];
  bool _loading = false;
  Object? _error;

  /// Favourites first, then in order, as the API lists them.
  List<Label> get labels => _labels;
  bool get isLoading => _loading;
  Object? get error => _error;

  LabelsApi get api => _api;

  Label? byId(String? id) =>
      id == null ? null : _labels.where((l) => l.id == id).firstOrNull;

  Future<void> load() async {
    final current = token();
    if (current == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _labels = await _api.listLabels(current);
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String _token() {
    final current = token();
    if (current == null) throw StateError('signed out');
    return current;
  }

  Future<Label> create(LabelDraft draft) async {
    final label = await _api.createLabel(_token(), draft);
    await load();
    return label;
  }

  Future<void> update(Label label, LabelDraft changes) async {
    await _api.updateLabel(_token(), label.id, changes);
    await load();
  }

  Future<void> delete(Label label) async {
    await _api.deleteLabel(_token(), label.id);
    await load();
  }
}
