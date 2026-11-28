import 'package:flutter/widgets.dart';

/// Lets a persistent detail pane protect unsaved input before shell navigation.
class WorkspaceEdits {
  Object? _owner;
  Future<bool> Function()? _canLeave;
  bool _asking = false;
  bool get hasOwner => _owner != null;

  void register(Object owner, Future<bool> Function() canLeave) {
    _owner = owner;
    _canLeave = canLeave;
  }

  void unregister(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _canLeave = null;
  }

  Future<bool> canLeave() async {
    if (_asking) return false;
    _asking = true;
    try {
      return await (_canLeave?.call() ?? Future.value(true));
    } finally {
      _asking = false;
    }
  }
}

class WorkspaceEditsScope extends InheritedWidget {
  const WorkspaceEditsScope({super.key, required this.edits, required super.child});
  final WorkspaceEdits edits;
  static WorkspaceEdits? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<WorkspaceEditsScope>()?.edits;
  @override
  bool updateShouldNotify(WorkspaceEditsScope oldWidget) => edits != oldWidget.edits;
}
