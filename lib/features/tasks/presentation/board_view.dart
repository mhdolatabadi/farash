import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/calendar/calendar_settings.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/core/widgets/hover_reveal.dart';
import 'package:menval/features/labels/application/labels_controller.dart';
import 'package:menval/features/tasks/application/tasks_controller.dart';
import 'package:menval/features/tasks/data/task.dart';
import 'package:menval/features/tasks/presentation/section_dialogs.dart';
import 'package:menval/features/tasks/presentation/task_tile.dart';

/// How a project shows its tasks.
enum ProjectLayout { list, board }

/// Each project's layout, remembered on this device.
class ProjectLayouts {
  ProjectLayouts({CalendarSettingsStore? store}) : _store = store;

  final CalendarSettingsStore? _store;

  static String _key(String projectId) => 'project_layout_$projectId';

  Future<ProjectLayout> read(String projectId) async {
    try {
      final saved = await _store?.read(_key(projectId));
      return saved == ProjectLayout.board.name
          ? ProjectLayout.board
          : ProjectLayout.list;
    } catch (_) {
      return ProjectLayout.list;
    }
  }

  Future<void> write(String projectId, ProjectLayout layout) async {
    try {
      await _store?.write(_key(projectId), layout.name);
    } catch (_) {
      // The layout holds for this session.
    }
  }
}

/// Narrower than this, columns page one at a time.
const boardPagingBreakpoint = 600.0;
const _columnWidth = 300.0;

/// A project as a board: tasks without a section, then one column per
/// section, then a column to add a section. Cards drag between and within
/// columns; subtasks move with their task and show as progress on the card.
class ProjectBoard extends StatefulWidget {
  const ProjectBoard({
    super.key,
    required this.tasks,
    required this.onToggle,
    required this.onOpen,
    required this.onMove,
    required this.onAddTask,
    required this.onAddSection,
    required this.onSectionAction,
    this.labels,
    this.bottomInset = 0,
  });

  final TasksController tasks;
  final LabelsController? labels;
  final ValueChanged<Task> onToggle, onOpen;

  /// Puts the task into the section (null: none) with these top-level ids
  /// in order.
  final void Function(Task task, String? sectionId, List<String> ids) onMove;

  /// Adds a task into the section; null for tasks without a section.
  final ValueChanged<Section?> onAddTask;

  /// Null where sections are not available.
  final VoidCallback? onAddSection;
  final void Function(Section, SectionAction) onSectionAction;

  /// Room left for a bar floating over the bottom.
  final double bottomInset;

  @override
  State<ProjectBoard> createState() => _ProjectBoardState();
}

class _ProjectBoardState extends State<ProjectBoard> {
  late final _pages = PageController(viewportFraction: .88);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// [ids] of the column with [task] put before [before] (null: at the end).
  static List<String> _placed(List<Task> column, Task task, Task? before) {
    final ids = [
      for (final t in column)
        if (t.id != task.id) t.id,
    ];
    final at = before == null ? ids.length : ids.indexOf(before.id);
    ids.insert(at < 0 ? ids.length : at, task.id);
    return ids;
  }

  Widget _column(
    BuildContext context,
    Section? section, {
    required bool paging,
  }) {
    final theme = Theme.of(context);
    final cards = widget.tasks.openIn(section?.id);
    final sections = widget.tasks.sections;
    void drop(Task task, Task? before) {
      final ids = _placed(cards, task, before);
      final unchanged =
          widget.tasks.sectionOf(task) == section?.id &&
          ids.join(',') == cards.map((t) => t.id).join(',');
      if (!unchanged) widget.onMove(task, section?.id, ids);
    }

    // A drop line shows where the card will land: before the card, or at
    // the column's end for the [fill] target behind the cards.
    Widget slot(Task? before, Widget child, {bool fill = false}) =>
        DragTarget<Task>(
          onAcceptWithDetails: (d) => drop(d.data, before),
          builder: (context, candidates, _) {
            final line = AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: candidates.isEmpty ? 0 : 4,
              margin: EdgeInsets.symmetric(
                horizontal: fill ? Space.sm : 0,
                vertical: candidates.isEmpty ? 0 : Space.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              children: fill ? [child, line] : [line, child],
            );
          },
        );

    Widget card(Task task) {
      final children = widget.tasks.openChildren(task);
      final tile = TaskTile(
        task: task,
        dense: true,
        divider: false,
        labels: [for (final id in task.labelIds) ?widget.labels?.byId(id)],
        onToggle: () => widget.onToggle(task),
        onOpen: () => widget.onOpen(task),
      );
      final body = Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            tile,
            // The subtasks fold into the card as its progress.
            if (children.isNotEmpty && task.subtaskCount == 0)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Space.keyline,
                  0,
                  Space.md,
                  Space.sm,
                ),
                child: Text(
                  '${persianDigits(children.length)} زیرکار',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
      final feedback = SizedBox(
        width: _columnWidth - Space.md * 2,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(14),
          child: Directionality(
            textDirection: Directionality.of(context),
            child: tile,
          ),
        ),
      );
      final dragging = Opacity(opacity: .35, child: body);
      return Padding(
        key: ValueKey('card-${task.id}'),
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: paging || HoverReveal.isTouch(context)
            ? LongPressDraggable<Task>(
                data: task,
                feedback: feedback,
                childWhenDragging: dragging,
                child: body,
              )
            : Draggable<Task>(
                data: task,
                feedback: feedback,
                childWhenDragging: dragging,
                child: body,
              ),
      );
    }

    final index = section == null ? -1 : sections.indexOf(section);
    return Padding(
      key: ValueKey('column-${section?.id ?? 'none'}'),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: SoftWell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.md,
                Space.xs,
                0,
                Space.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      section?.name ?? 'بدون بخش',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    persianDigits(cards.length),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: section == null
                        ? 'افزودن کار بدون بخش'
                        : 'افزودن کار به «${section.name}»',
                    onPressed: () => widget.onAddTask(section),
                    icon: const Icon(Icons.add),
                  ),
                  if (section != null)
                    PopupMenuButton<SectionAction>(
                      tooltip: 'گزینه‌های بخش',
                      onSelected: (a) => widget.onSectionAction(section, a),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: SectionAction.rename,
                          child: Text('تغییر نام'),
                        ),
                        if (index > 0)
                          const PopupMenuItem(
                            value: SectionAction.moveUp,
                            child: Text('انتقال به قبل'),
                          ),
                        if (index < sections.length - 1)
                          const PopupMenuItem(
                            value: SectionAction.moveDown,
                            child: Text('انتقال به بعد'),
                          ),
                        const PopupMenuItem(
                          value: SectionAction.delete,
                          child: Text('حذف بخش'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Anywhere below the cards takes a drop at the column's end.
            Expanded(
              child: slot(
                null,
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      Space.sm,
                      0,
                      Space.sm,
                      Space.md + widget.bottomInset,
                    ),
                    children: [
                      for (final task in cards) slot(task, card(task)),
                      if (cards.isEmpty)
                        SizedBox(
                          height: 72,
                          child: Center(
                            child: Text(
                              'کاری را اینجا رها کنید.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                fill: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final paging = constraints.maxWidth < boardPagingBreakpoint;
      final columns = <Widget>[
        _column(context, null, paging: paging),
        for (final section in widget.tasks.sections)
          _column(context, section, paging: paging),
        if (widget.onAddSection != null)
          Padding(
            key: const ValueKey('column-add'),
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: Align(
              alignment: Alignment.topCenter,
              child: OutlinedButton.icon(
                onPressed: widget.onAddSection,
                icon: const Icon(Icons.view_column_outlined),
                label: const Text('افزودن ستون'),
              ),
            ),
          ),
      ];
      if (paging) {
        return PageView(controller: _pages, padEnds: false, children: columns);
      }
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter - Space.xs,
        ),
        children: [
          for (final column in columns)
            SizedBox(width: _columnWidth, child: column),
        ],
      );
    },
  );
}
