import 'package:flutter/material.dart';

/// A project (list) or a folder of projects. Every account has one Inbox,
/// which cannot be renamed, moved, archived or deleted.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.color,
    this.parentId,
    this.isInbox = false,
    this.isFavorite = false,
    this.isArchived = false,
    this.sortOrder = 0,
    this.kind = ProjectKind.project,
    this.openTasks = 0,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    parentId: json['parent_id'] as String?,
    name: json['name'] as String,
    color: json['color'] as String? ?? ProjectColor.defaultHex,
    isInbox: json['is_inbox'] as bool? ?? false,
    isFavorite: json['is_favorite'] as bool? ?? false,
    isArchived: json['is_archived'] as bool? ?? false,
    sortOrder: json['sort_order'] as int? ?? 0,
    kind: json['kind'] == 'folder' ? ProjectKind.folder : ProjectKind.project,
    openTasks: json['open_tasks'] as int? ?? 0,
  );

  final String id;
  final String? parentId;
  final String name;

  /// A `#rrggbb` color.
  final String color;
  final bool isInbox;
  final bool isFavorite;
  final bool isArchived;
  final int sortOrder;
  final ProjectKind kind;
  final int openTasks;

  bool get isFolder => kind == ProjectKind.folder;

  /// The name to show: the Inbox is always «صندوق ورودی».
  String get displayName => isInbox ? 'صندوق ورودی' : name;

  Color get swatch => ProjectColor.parse(color);

  Project copyWith({
    String? name,
    String? color,
    bool? isFavorite,
    bool? isArchived,
    int? sortOrder,
  }) => Project(
    id: id,
    parentId: parentId,
    name: name ?? this.name,
    color: color ?? this.color,
    isInbox: isInbox,
    isFavorite: isFavorite ?? this.isFavorite,
    isArchived: isArchived ?? this.isArchived,
    sortOrder: sortOrder ?? this.sortOrder,
    kind: kind,
    openTasks: openTasks,
  );
}

enum ProjectKind { project, folder }

/// The colors offered when creating or editing a project.
class ProjectColor {
  const ProjectColor(this.hex, this.label);

  /// `#rrggbb`, as the API stores it.
  final String hex;
  final String label;

  Color get color => parse(hex);

  /// The API's default project color.
  static const defaultHex = '#7c3aed';

  static const all = [
    ProjectColor('#7c3aed', 'بنفش'),
    ProjectColor('#2563eb', 'آبی'),
    ProjectColor('#0ea5e9', 'آسمانی'),
    ProjectColor('#0f8b7c', 'سبزآبی'),
    ProjectColor('#16a34a', 'سبز'),
    ProjectColor('#84cc16', 'لیمویی'),
    ProjectColor('#eab308', 'زرد'),
    ProjectColor('#f97316', 'نارنجی'),
    ProjectColor('#dc2626', 'قرمز'),
    ProjectColor('#db2777', 'سرخابی'),
    ProjectColor('#a16207', 'قهوه‌ای'),
    ProjectColor('#64748b', 'خاکستری'),
  ];

  /// Reads `#rrggbb`; anything else shows as grey.
  static Color parse(String hex) {
    final value = hex.startsWith('#') ? hex.substring(1) : hex;
    final parsed = value.length == 6 ? int.tryParse(value, radix: 16) : null;
    return parsed == null
        ? const Color(0xFF64748B)
        : Color(0xFF000000 | parsed);
  }
}
