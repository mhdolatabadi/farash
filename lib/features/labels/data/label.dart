import 'package:flutter/painting.dart';

/// A label, as the API returns it: the owner's own tag, shared across
/// their projects.
class Label {
  const Label({
    required this.id,
    required this.name,
    this.color = defaultColor,
    this.isFavorite = false,
    this.sortOrder = 0,
    this.openTaskCount = 0,
  });

  factory Label.fromJson(Map<String, dynamic> json) => Label(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String? ?? defaultColor,
    isFavorite: json['is_favorite'] as bool? ?? false,
    sortOrder: json['sort_order'] as int? ?? 0,
    openTaskCount: json['open_task_count'] as int? ?? 0,
  );

  static const defaultColor = '#8B88A0';

  final String id;
  final String name;

  /// #RRGGBB.
  final String color;
  final bool isFavorite;
  final int sortOrder;
  final int openTaskCount;

  Color get swatch {
    final value = int.tryParse(color.replaceFirst('#', ''), radix: 16);
    return Color(0xFF000000 | (value ?? 0x8B88A0));
  }

  /// "@name", as labels read in Persian task apps.
  String get tag => '@$name';
}

/// Fields for a new label, or the fields to change on one.
class LabelDraft {
  const LabelDraft({this.name, this.color, this.isFavorite});

  final String? name;
  final String? color;
  final bool? isFavorite;

  Map<String, Object?> toJson() => {
    'name': ?name,
    'color': ?color,
    'is_favorite': ?isFavorite,
  };
}
