import 'package:flutter/material.dart';

/// A task, as the API returns it.
class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    this.sectionId,
    this.parentId,
    this.description = '',
    this.priority = TaskPriority.p4,
    this.sortOrder = 0,
    this.completedAt,
    this.subtaskCount = 0,
    this.completedSubtaskCount = 0,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    sectionId: json['section_id'] as String?,
    parentId: json['parent_id'] as String?,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    priority: TaskPriority.fromLevel(json['priority'] as int? ?? 4),
    sortOrder: json['sort_order'] as int? ?? 0,
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.parse(json['completed_at'] as String),
    subtaskCount: json['subtask_count'] as int? ?? 0,
    completedSubtaskCount: json['completed_subtask_count'] as int? ?? 0,
  );

  final String id;
  final String projectId;

  /// The section within the project, if any.
  final String? sectionId;

  /// The task this one is a subtask of; it shares that task's project and
  /// section.
  final String? parentId;
  final String title;

  /// Markdown text; empty when there is none.
  final String description;
  final TaskPriority priority;
  final int sortOrder;
  final DateTime? completedAt;

  /// Direct subtasks, including completed ones that may not be loaded.
  final int subtaskCount;
  final int completedSubtaskCount;

  bool get isCompleted => completedAt != null;
  bool get hasSubtasks => subtaskCount > 0;

  Task copyWith({
    String? projectId,
    String? sectionId,
    bool clearSection = false,
    String? parentId,
    bool clearParent = false,
    String? title,
    String? description,
    TaskPriority? priority,
    int? sortOrder,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? subtaskCount,
    int? completedSubtaskCount,
  }) => Task(
    id: id,
    projectId: projectId ?? this.projectId,
    sectionId: clearSection ? null : (sectionId ?? this.sectionId),
    parentId: clearParent ? null : (parentId ?? this.parentId),
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    sortOrder: sortOrder ?? this.sortOrder,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    subtaskCount: subtaskCount ?? this.subtaskCount,
    completedSubtaskCount: completedSubtaskCount ?? this.completedSubtaskCount,
  );
}

/// P1 is the most urgent; P4 is the default "no priority".
enum TaskPriority {
  p1(1, 'اولویت ۱', Color(0xFFD1453B)),
  p2(2, 'اولویت ۲', Color(0xFFEB8909)),
  p3(3, 'اولویت ۳', Color(0xFF246FE0)),
  p4(4, 'اولویت ۴', Color(0xFF8A8A8A));

  const TaskPriority(this.level, this.label, this.color);

  /// The API's 1–4 value.
  final int level;
  final String label;
  final Color color;

  static TaskPriority fromLevel(int level) =>
      values.firstWhere((p) => p.level == level, orElse: () => p4);
}

/// A named group of tasks inside a project.
class Section {
  const Section({
    required this.id,
    required this.projectId,
    required this.name,
    this.sortOrder = 0,
    this.isCollapsed = false,
  });

  factory Section.fromJson(Map<String, dynamic> json) => Section(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    name: json['name'] as String,
    sortOrder: json['sort_order'] as int? ?? 0,
    isCollapsed: json['is_collapsed'] as bool? ?? false,
  );

  final String id;
  final String projectId;
  final String name;
  final int sortOrder;
  final bool isCollapsed;

  Section copyWith({String? name, int? sortOrder, bool? isCollapsed}) =>
      Section(
        id: id,
        projectId: projectId,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        isCollapsed: isCollapsed ?? this.isCollapsed,
      );
}
