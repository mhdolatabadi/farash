import 'package:flutter/material.dart';

/// Geometry shared by every Menval control, including compact desktop rows.
abstract final class MenvalDesignTokens {
  static const controlHeight = 48.0;
  static const controlRadius = 12.0;
  static const checkboxSize = 20.0;
  static const checkboxGlyph = 14.0;
  static const iconSize = 20.0;
  static const taskRowHeight = 52.0;
  static const motion = Duration(milliseconds: 120);
  static const radius = BorderRadius.all(Radius.circular(controlRadius));

  // Reserved palette proposals; intentionally absent from appearance settings.
  static const futureAccents = <String, (Color, Color)>{
    'gray-gold': (Color(0xFF343532), Color(0xFFCFAD66)),
    'burgundy-gold': (Color(0xFF3B222D), Color(0xFFD8B16A)),
    'navy-neon': (Color(0xFF18293B), Color(0xFFBBF847)),
  };
}
