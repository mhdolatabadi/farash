import 'package:flutter/material.dart';

/// A task, as the API returns it.
class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.priority = TaskPriority.p4,
    this.sortOrder = 0,
    this.completedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    projectId: json['project_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    priority: TaskPriority.fromLevel(json['priority'] as int? ?? 4),
    sortOrder: json['sort_order'] as int? ?? 0,
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.parse(json['completed_at'] as String),
  );

  final String id;
  final String projectId;
  final String title;

  /// Markdown text; empty when there is none.
  final String description;
  final TaskPriority priority;
  final int sortOrder;
  final DateTime? completedAt;

  bool get isCompleted => completedAt != null;

  Task copyWith({
    String? projectId,
    String? title,
    String? description,
    TaskPriority? priority,
    int? sortOrder,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => Task(
    id: id,
    projectId: projectId ?? this.projectId,
    title: title ?? this.title,
    description: description ?? this.description,
    priority: priority ?? this.priority,
    sortOrder: sortOrder ?? this.sortOrder,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
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
