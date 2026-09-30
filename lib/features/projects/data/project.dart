import 'package:flutter/material.dart';

/// A project (list). Every account has one Inbox, which cannot be renamed,
/// moved, archived or deleted.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.color,
    this.parentId,
    this.isInbox = false,
    this.isFavorite = false,
    this.isArchived = false,
    this.childOrder = 0,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    parentId: json['parentId'] as String?,
    name: json['name'] as String,
    color: json['color'] as String,
    isInbox: json['isInbox'] as bool? ?? false,
    isFavorite: json['isFavorite'] as bool? ?? false,
    isArchived: json['isArchived'] as bool? ?? false,
    childOrder: json['childOrder'] as int? ?? 0,
  );

  final String id;
  final String? parentId;
  final String name;
  final String color;
  final bool isInbox;
  final bool isFavorite;
  final bool isArchived;
  final int childOrder;

  /// The name to show: the Inbox is always «صندوق ورودی».
  String get displayName => isInbox ? 'صندوق ورودی' : name;

  Color get swatch => ProjectColor.of(color).color;

  Project copyWith({
    String? name,
    String? color,
    bool? isFavorite,
    bool? isArchived,
  }) => Project(
    id: id,
    parentId: parentId,
    name: name ?? this.name,
    color: color ?? this.color,
    isInbox: isInbox,
    isFavorite: isFavorite ?? this.isFavorite,
    isArchived: isArchived ?? this.isArchived,
    childOrder: childOrder,
  );
}

/// The project palette, matching the API's color names.
class ProjectColor {
  const ProjectColor(this.key, this.label, this.color);

  final String key;
  final String label;
  final Color color;

  static const defaultKey = 'charcoal';

  static const all = [
    ProjectColor('berry_red', 'تمشکی', Color(0xFFB8255F)),
    ProjectColor('red', 'قرمز', Color(0xFFDB4035)),
    ProjectColor('orange', 'نارنجی', Color(0xFFFF9933)),
    ProjectColor('yellow', 'زرد', Color(0xFFFAD000)),
    ProjectColor('olive_green', 'زیتونی', Color(0xFFAFB83B)),
    ProjectColor('lime_green', 'لیمویی', Color(0xFF7ECC49)),
    ProjectColor('green', 'سبز', Color(0xFF299438)),
    ProjectColor('mint_green', 'نعنایی', Color(0xFF6ACCBC)),
    ProjectColor('teal', 'سبزآبی', Color(0xFF158FAD)),
    ProjectColor('sky_blue', 'آسمانی', Color(0xFF14AAF5)),
    ProjectColor('light_blue', 'آبی روشن', Color(0xFF96C3EB)),
    ProjectColor('blue', 'آبی', Color(0xFF4073FF)),
    ProjectColor('grape', 'انگوری', Color(0xFF884DFF)),
    ProjectColor('violet', 'بنفش', Color(0xFFAF38EB)),
    ProjectColor('lavender', 'اسطوخودوسی', Color(0xFFEB96EB)),
    ProjectColor('magenta', 'سرخابی', Color(0xFFE05194)),
    ProjectColor('salmon', 'صورتی', Color(0xFFFF8D85)),
    ProjectColor('charcoal', 'زغالی', Color(0xFF808080)),
    ProjectColor('grey', 'خاکستری', Color(0xFFB8B8B8)),
    ProjectColor('taupe', 'قهوه‌ای', Color(0xFFCCAC93)),
  ];

  static ProjectColor of(String key) =>
      all.firstWhere((c) => c.key == key, orElse: () => all[17]);
}
