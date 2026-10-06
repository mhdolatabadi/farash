import 'package:flutter/material.dart';

/// Every color the app's look depends on, for one brightness: Material
/// roles plus the glass backdrop and panes. Swapping a palette restyles the
/// whole app without touching widgets.
@immutable
class FarashColors {
  const FarashColors({
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.selected,
    required this.onSelected,
    required this.backdrop,
    required this.glow,
    required this.pane,
    required this.paneBorder,
    required this.shadow,
  });

  final Color primary;
  final Color onPrimary;

  /// A warm second voice for highlights such as today and selection marks.
  final Color accent;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;

  /// Selected rows and chips.
  final Color selected;
  final Color onSelected;

  /// The diagonal wash behind everything, three stops.
  final List<Color> backdrop;

  /// A soft light pooled on the backdrop.
  final Color glow;

  /// The translucent tint and edge of glass panes.
  final Color pane;
  final Color paneBorder;
  final Color shadow;
}

@immutable
class FarashPalette {
  const FarashPalette({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final FarashColors light;
  final FarashColors dark;

  FarashColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Pomegranate (#43): a warm red primary on ivory with a straw accent.
  static const pomegranate = FarashPalette(
    name: 'pomegranate',
    light: FarashColors(
      primary: Color(0xFFA6324A),
      onPrimary: Colors.white,
      accent: Color(0xFF9C5C14),
      surface: Color(0xFFFFFBF8),
      onSurface: Color(0xFF2D1C20),
      onSurfaceVariant: Color(0xFF6E5A5D),
      selected: Color(0xFFF5DFE2),
      onSelected: Color(0xFF5C1023),
      backdrop: [Color(0xFFF4DFDF), Color(0xFFFDF9F4), Color(0xFFF1E6D2)],
      glow: Color(0xB3FFFFFF),
      pane: Color(0xB8FFFFFF),
      paneBorder: Color(0xE6FFFFFF),
      shadow: Color(0x142D1C20),
    ),
    dark: FarashColors(
      primary: Color(0xFFFFB0BE),
      onPrimary: Color(0xFF5C1023),
      accent: Color(0xFFEDBB72),
      surface: Color(0xFF2A1B1F),
      onSurface: Color(0xFFF6E8EA),
      onSurfaceVariant: Color(0xFFCDB8BB),
      selected: Color(0xFF4E2A32),
      onSelected: Color(0xFFF6E8EA),
      backdrop: [Color(0xFF3A1A22), Color(0xFF1A1114), Color(0xFF2B2216)],
      glow: Color(0x338C3A4C),
      pane: Color(0xE62A1B1F),
      paneBorder: Color(0x29FFB0BE),
      shadow: Color(0x4D000000),
    ),
  );
}

/// Hands the palette's glass colors to the backdrop and panes.
class FarashGlassColors extends ThemeExtension<FarashGlassColors> {
  const FarashGlassColors(this.colors);

  final FarashColors colors;

  static FarashColors of(BuildContext context) =>
      Theme.of(context).extension<FarashGlassColors>()?.colors ??
      FarashPalette.pomegranate.of(Theme.of(context).brightness);

  @override
  FarashGlassColors copyWith({FarashColors? colors}) =>
      FarashGlassColors(colors ?? this.colors);

  @override
  FarashGlassColors lerp(FarashGlassColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
