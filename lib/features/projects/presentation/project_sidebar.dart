import 'package:flutter/material.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/core/widgets/hover_reveal.dart';
import 'package:farash/features/labels/application/labels_controller.dart';
import 'package:farash/features/labels/data/label.dart';
import 'package:farash/features/labels/presentation/label_widgets.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/project_editor.dart';
import 'package:farash/features/projects/presentation/project_messages.dart';
import 'package:farash/features/tasks/presentation/due_tasks_view.dart';

/// The navigation list: Inbox, the views across projects, favourites,
/// the project tree and labels, with the progress and the account pinned
/// under it. Used as the phone drawer and the wide-screen sidebar, on the
/// soft ground: compact rows in labelled groups, the open row standing up
/// as a raised pill and everything else flat.
class ProjectSidebar extends StatelessWidget {
  const ProjectSidebar({
    super.key,
    required this.controller,
    required this.selectedId,
    required this.onSelect,
    required this.onOpenArchived,
    required this.header,
    this.tools,
    this.footer,
    this.account,
    this.selectedView,
    this.onSelectView,
    this.viewCounts = const {},
    this.labels,
    this.selectedLabelId,
    this.onSelectLabel,
  });

  final ProjectsController controller;
  final String? selectedId;
  final ValueChanged<Project> onSelect;
  final VoidCallback onOpenArchived;

  /// The app's name and search, at the top.
  final Widget header;

  /// Destinations that are not lists, such as Focus, under the views.
  final List<Widget>? tools;

  /// Pinned under the list, as the progress summary.
  final Widget? footer;

  /// The account row, pinned at the very bottom.
  final Widget? account;

  /// The view across projects that is open, if any.
  final DueView? selectedView;
  final ValueChanged<DueView>? onSelectView;

  /// Open-task counts shown beside views, such as today's.
  final Map<DueView, int> viewCounts;

  /// The account's labels, listed under the projects.
  final LabelsController? labels;
  final String? selectedLabelId;
  final ValueChanged<Label>? onSelectLabel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final inbox = controller.inbox;
        final favorites = controller.favorites;
        final tree = controller.tree;
        Widget hint(String text) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.md,
            Space.xs,
            Space.md,
            Space.sm,
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
        final tools = this.tools ?? const <Widget>[];
        final footer = this.footer;
        final account = this.account;
        return SidebarTheme(
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.md,
                      Space.md,
                      Space.md,
                      Space.lg,
                    ),
                    children:
                        <Widget>[
                              header,
                              const SizedBox(height: Space.md),
                              if (inbox != null)
                                _ProjectTile(
                                  project: inbox,
                                  icon: Icons.inbox_outlined,
                                  selected: inbox.id == selectedId,
                                  onTap: () => onSelect(inbox),
                                  controller: controller,
                                ),
                              if (onSelectView != null)
                                for (final view in DueView.values)
                                  SidebarRow(
                                    key: ValueKey('view-${view.name}'),
                                    selected: view == selectedView,
                                    child: ListTile(
                                      selected: view == selectedView,
                                      leading: Icon(view.icon),
                                      title: Text(view.title),
                                      trailing: SidebarCount(viewCounts[view]),
                                      onTap: () => onSelectView!(view),
                                    ),
                                  ),
                              if (controller.error != null &&
                                  controller.projects.isEmpty)
                                _LoadError(onRetry: controller.load),
                              if (tools.isNotEmpty) ...[
                                const _SectionTitle('ابزارها'),
                                ...tools,
                              ],
                              if (favorites.isNotEmpty) ...[
                                const _SectionTitle('علاقه‌مندی‌ها'),
                                for (final project in favorites)
                                  _ProjectTile(
                                    key: ValueKey('favorite-${project.id}'),
                                    project: project,
                                    selected: project.id == selectedId,
                                    onTap: () => onSelect(project),
                                    controller: controller,
                                  ),
                              ],
                              _SectionTitle(
                                'پروژه‌ها',
                                actions: [
                                  _SectionAction(
                                    icon: Icons.inventory_2_outlined,
                                    tooltip: 'پروژه‌های بایگانی‌شده',
                                    onPressed: onOpenArchived,
                                  ),
                                  _SectionAction(
                                    tooltip: 'پروژهٔ تازه',
                                    onPressed: () => showProjectEditor(
                                      context,
                                      controller: controller,
                                      onCreated: onSelect,
                                    ),
                                  ),
                                ],
                              ),
                              if (tree.isEmpty &&
                                  controller.projects.isNotEmpty)
                                hint(
                                  'کارها را در پروژه‌ها دسته‌بندی کنید؛ مثلاً «کار» یا «خانه».',
                                ),
                              for (final node in tree)
                                _ProjectTile(
                                  key: ValueKey('tree-${node.project.id}'),
                                  project: node.project,
                                  depth: node.depth,
                                  selected: node.project.id == selectedId,
                                  onTap: () => onSelect(node.project),
                                  controller: controller,
                                ),
                              if (labels case final labels?) ...[
                                _SectionTitle(
                                  'برچسب‌ها',
                                  actions: [
                                    _SectionAction(
                                      tooltip: 'برچسب تازه',
                                      onPressed: () async {
                                        final created = await showLabelEditor(
                                          context,
                                          controller: labels,
                                        );
                                        if (created != null) {
                                          onSelectLabel?.call(created);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                if (labels.labels.isEmpty)
                                  hint(
                                    'کارهای مرتبط را از پروژه‌های مختلف با برچسبی مثل «@تلفن» کنار هم ببینید.',
                                  ),
                                for (final label in labels.labels)
                                  _LabelTile(
                                    key: ValueKey('label-${label.id}'),
                                    label: label,
                                    controller: labels,
                                    selected: label.id == selectedLabelId,
                                    onTap: () => onSelectLabel?.call(label),
                                  ),
                              ],
                            ]
                            .map(
                              (row) => Material(
                                type: MaterialType.transparency,
                                child: row,
                              ),
                            )
                            .toList(),
                  ),
                ),
                if (footer != null || account != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: Soft.hairline(context)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.md,
                        Space.sm,
                        Space.md,
                        Space.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [?footer, ?account],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The sidebar's one row style: an 18 icon, a medium title and a quiet
/// count; 36 high where a pointer is used and 48 on touch.
class SidebarTheme extends StatelessWidget {
  const SidebarTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pointer = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => MediaQuery.sizeOf(context).width >= 840,
    };
    return ListTileTheme(
      data: ListTileThemeData(
        dense: true,
        minTileHeight: pointer ? 36 : 48,
        minLeadingWidth: 18,
        minVerticalPadding: 0,
        visualDensity: VisualDensity.compact,
        horizontalTitleGap: Space.md,
        contentPadding: const EdgeInsetsDirectional.only(
          start: Space.md,
          end: Space.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SidebarRow.radius),
        ),
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        selectedColor: scheme.primary,
        selectedTileColor: Colors.transparent,
        titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        leadingAndTrailingTextStyle: theme.textTheme.labelMedium,
      ),
      child: IconTheme.merge(data: const IconThemeData(size: 18), child: child),
    );
  }
}

/// A sidebar row; the open one stands off the ground as a raised pill.
class SidebarRow extends StatelessWidget {
  const SidebarRow({super.key, required this.selected, required this.child});

  /// The corner of every row and of the open row's pill.
  static const radius = 10.0;

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final row = Material(type: MaterialType.transparency, child: child);
    if (!selected) return row;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Soft.ground(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: Soft.hairline(context),
          ),
          shadows: Soft.raised(context, depth: 3),
        ),
        child: row,
      ),
    );
  }
}

/// A muted count at a row's end; nothing when there is none.
class SidebarCount extends StatelessWidget {
  const SidebarCount(this.count, {super.key});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    if (count == null || count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Space.sm),
      child: Semantics(
        label: '${persianDigits(count)} کار',
        excludeSemantics: true,
        child: Text(
          persianDigits(count),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// A quiet button beside a section's name, such as add.
class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.tooltip,
    required this.onPressed,
    this.icon = Icons.add,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

enum _LabelAction { edit, favorite, delete }

class _LabelTile extends StatelessWidget {
  const _LabelTile({
    super.key,
    required this.label,
    required this.controller,
    required this.selected,
    required this.onTap,
  });

  final Label label;
  final LabelsController controller;
  final bool selected;
  final VoidCallback onTap;

  Future<void> _run(BuildContext context, _LabelAction action) async {
    try {
      switch (action) {
        case _LabelAction.edit:
          await showLabelEditor(context, controller: controller, label: label);
        case _LabelAction.favorite:
          await controller.update(
            label,
            LabelDraft(isFavorite: !label.isFavorite),
          );
        case _LabelAction.delete:
          if (await confirmLabelDelete(context, label)) {
            await controller.delete(label);
          }
      }
    } catch (error) {
      if (context.mounted) showProjectError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SidebarRow(
      selected: selected,
      child: HoverRegion(
        child: ListTile(
          selected: selected,
          onTap: onTap,
          leading: Icon(Icons.sell_outlined, size: 18, color: label.swatch),
          title: Text(label.tag, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: HoverSwap(
            idle: SidebarCount(label.openTaskCount),
            active: PopupMenuButton<_LabelAction>(
              tooltip: 'گزینه‌های برچسب',
              onSelected: (action) => _run(context, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _LabelAction.edit,
                  child: Text('ویرایش'),
                ),
                PopupMenuItem(
                  value: _LabelAction.favorite,
                  child: Text(
                    label.isFavorite
                        ? 'حذف از علاقه‌مندی‌ها'
                        : 'افزودن به علاقه‌مندی‌ها',
                  ),
                ),
                const PopupMenuItem(
                  value: _LabelAction.delete,
                  child: Text('حذف'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A group's name: small and muted, closer to its rows than to the
/// group above.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.md,
        Space.lg,
        Space.xs,
        Space.xs,
      ),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.cloud_off_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('پروژه‌ها بارگذاری نشدند'),
      trailing: TextButton(
        onPressed: onRetry,
        child: const Text('تلاش دوباره'),
      ),
    );
  }
}

enum _ProjectAction {
  edit,
  favorite,
  addChild,
  moveUp,
  moveDown,
  archive,
  delete,
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    super.key,
    required this.project,
    required this.selected,
    required this.onTap,
    required this.controller,
    this.depth = 0,
    this.icon,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;
  final ProjectsController controller;
  final int depth;
  final IconData? icon;

  Future<void> _run(BuildContext context, _ProjectAction action) async {
    try {
      switch (action) {
        case _ProjectAction.edit:
          await showProjectEditor(
            context,
            controller: controller,
            project: project,
          );
        case _ProjectAction.favorite:
          await controller.setFavorite(project, !project.isFavorite);
        case _ProjectAction.addChild:
          await showProjectEditor(
            context,
            controller: controller,
            parent: project,
          );
        case _ProjectAction.moveUp:
        case _ProjectAction.moveDown:
          final siblings = controller.siblingsOf(project);
          final index = siblings.indexWhere((p) => p.id == project.id);
          await controller.reorder(
            project,
            action == _ProjectAction.moveUp ? index - 1 : index + 1,
          );
        case _ProjectAction.archive:
          await controller.archive(project);
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text('«${project.displayName}» بایگانی شد.'),
                action: SnackBarAction(
                  label: 'برگرداندن',
                  onPressed: () => controller.unarchive(project),
                ),
              ),
            );
          }
        case _ProjectAction.delete:
          if (await confirmProjectDelete(context, project)) {
            await controller.delete(project);
          }
      }
    } catch (error) {
      if (context.mounted) showProjectError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final siblings = project.isInbox
        ? const <Project>[]
        : controller.siblingsOf(project);
    final index = siblings.indexWhere((p) => p.id == project.id);
    return SidebarRow(
      selected: selected,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: 16.0 * depth),
        child: HoverRegion(
          child: ListTile(
            selected: selected,
            onTap: onTap,
            leading: icon != null
                ? Icon(icon)
                : project.isFolder
                ? Icon(Icons.folder_outlined, size: 18, color: project.swatch)
                : Icon(Icons.circle, size: 10, color: project.swatch),
            title: Text(
              project.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: HoverSwap(
              idle: SidebarCount(project.openTasks),
              active: PopupMenuButton<_ProjectAction>(
                tooltip: 'گزینه‌های پروژه',
                onSelected: (action) => _run(context, action),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _ProjectAction.edit,
                    child: Text('ویرایش'),
                  ),
                  PopupMenuItem(
                    value: _ProjectAction.favorite,
                    child: Text(
                      project.isFavorite
                          ? 'حذف از علاقه‌مندی‌ها'
                          : 'افزودن به علاقه‌مندی‌ها',
                    ),
                  ),
                  if (!project.isInbox) ...[
                    PopupMenuItem(
                      value: _ProjectAction.addChild,
                      child: Text(
                        project.isFolder
                            ? 'افزودن پروژه به پوشه'
                            : 'افزودن زیرپروژه',
                      ),
                    ),
                    if (index > 0)
                      const PopupMenuItem(
                        value: _ProjectAction.moveUp,
                        child: Text('انتقال به بالا'),
                      ),
                    if (index >= 0 && index < siblings.length - 1)
                      const PopupMenuItem(
                        value: _ProjectAction.moveDown,
                        child: Text('انتقال به پایین'),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _ProjectAction.archive,
                      child: Text('بایگانی'),
                    ),
                    const PopupMenuItem(
                      value: _ProjectAction.delete,
                      child: Text('حذف'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks before deleting a project with everything in it.
Future<bool> confirmProjectDelete(BuildContext context, Project project) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('حذف «${project.displayName}»؟'),
      content: const Text(
        'کارهای این پروژه هم حذف می‌شوند و برگرداندنشان ممکن نیست؛ '
        'زیرپروژه‌هایش به سطح اول می‌روند. اگر فقط نمی‌خواهید ببینیدش، '
        'بایگانی‌اش کنید.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
