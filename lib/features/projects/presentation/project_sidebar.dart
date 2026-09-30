import 'package:flutter/material.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/project_editor.dart';
import 'package:farash/features/projects/presentation/project_messages.dart';

/// The navigation list: Inbox, favourites, the project tree and archived
/// projects. Used as the phone drawer and the wide-screen sidebar.
class ProjectSidebar extends StatelessWidget {
  const ProjectSidebar({
    super.key,
    required this.controller,
    required this.selectedId,
    required this.onSelect,
    required this.onOpenArchived,
    required this.header,
  });

  final ProjectsController controller;
  final String? selectedId;
  final ValueChanged<Project> onSelect;
  final VoidCallback onOpenArchived;

  /// The account row at the top.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final inbox = controller.inbox;
        final favorites = controller.favorites;
        final tree = controller.tree;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              header,
              const SizedBox(height: 8),
              if (inbox != null)
                _ProjectTile(
                  project: inbox,
                  icon: Icons.inbox_outlined,
                  selected: inbox.id == selectedId,
                  onTap: () => onSelect(inbox),
                  controller: controller,
                ),
              if (controller.error != null && controller.projects.isEmpty)
                _LoadError(onRetry: controller.load),
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
                action: IconButton(
                  tooltip: 'پروژهٔ تازه',
                  icon: const Icon(Icons.add),
                  onPressed: () => showProjectEditor(
                    context,
                    controller: controller,
                    onCreated: onSelect,
                  ),
                ),
              ),
              if (tree.isEmpty && controller.projects.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    'کارها را در پروژه‌ها دسته‌بندی کنید؛ مثلاً «کار» یا «خانه».',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
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
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('پروژه‌های بایگانی‌شده'),
                onTap: onOpenArchived,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, top: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ?action,
        ],
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
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 16.0 * depth),
      child: ListTile(
        selected: selected,
        onTap: onTap,
        leading: icon != null
            ? Icon(icon)
            : project.isFolder
            ? Icon(Icons.folder_outlined, color: project.swatch)
            : Icon(Icons.circle, size: 12, color: project.swatch),
        title: Text(
          project.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<_ProjectAction>(
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
                  project.isFolder ? 'افزودن پروژه به پوشه' : 'افزودن زیرپروژه',
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
