import 'package:flutter/material.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/project_messages.dart';
import 'package:farash/features/projects/presentation/project_sidebar.dart';

/// Archived projects, with restore and delete.
class ArchivedProjectsScreen extends StatelessWidget {
  const ArchivedProjectsScreen({super.key, required this.controller});

  final ProjectsController controller;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) showProjectError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('پروژه‌های بایگانی‌شده')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final projects = controller.archivedProjects;
          if (projects.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'پروژهٔ بایگانی‌شده‌ای ندارید.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final project in projects)
                    _ArchivedTile(
                      project: project,
                      onRestore: () =>
                          _run(context, () => controller.unarchive(project)),
                      onDelete: () => _run(context, () async {
                        if (await confirmProjectDelete(context, project)) {
                          await controller.delete(project);
                        }
                      }),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArchivedTile extends StatelessWidget {
  const _ArchivedTile({
    required this.project,
    required this.onRestore,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        project.isFolder ? Icons.folder_outlined : Icons.circle,
        size: project.isFolder ? null : 12,
        color: project.swatch,
      ),
      title: Text(
        project.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'برگرداندن از بایگانی',
            icon: const Icon(Icons.unarchive_outlined),
            onPressed: onRestore,
          ),
          IconButton(
            tooltip: 'حذف',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
