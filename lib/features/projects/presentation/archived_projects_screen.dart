import 'package:flutter/material.dart';
import 'package:farash/features/projects/application/projects_controller.dart';
import 'package:farash/features/projects/data/project.dart';
import 'package:farash/features/projects/presentation/project_messages.dart';
import 'package:farash/features/projects/presentation/project_sidebar.dart';

/// Archived projects, with restore and delete.
class ArchivedProjectsScreen extends StatefulWidget {
  const ArchivedProjectsScreen({super.key, required this.controller});

  final ProjectsController controller;

  @override
  State<ArchivedProjectsScreen> createState() => _ArchivedProjectsScreenState();
}

class _ArchivedProjectsScreenState extends State<ArchivedProjectsScreen> {
  late Future<List<Project>> _archived = widget.controller.archived();

  void _reload() {
    setState(() {
      _archived = widget.controller.archived();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } catch (error) {
      if (mounted) showProjectError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('پروژه‌های بایگانی‌شده')),
      body: FutureBuilder<List<Project>>(
        future: _archived,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(projectErrorMessage(snapshot.error!)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تلاش دوباره'),
                  ),
                ],
              ),
            );
          }
          final projects = snapshot.data!;
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
                    ListTile(
                      leading: Icon(
                        Icons.circle,
                        size: 12,
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
                            onPressed: () => _run(
                              () => widget.controller.unarchive(project),
                            ),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _run(() async {
                              if (await confirmProjectDelete(
                                context,
                                project,
                              )) {
                                await widget.controller.delete(project);
                              }
                            }),
                          ),
                        ],
                      ),
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
