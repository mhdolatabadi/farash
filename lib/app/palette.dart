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
    required this.overdue,
    required this.light,
    required this.mist,
    required this.edge,
    required this.priorities,
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

  /// The lamp: a warm light pooled on the backdrop, which moves with the
  /// project.
  final Color glow;

  /// A second, cool light across the room, so glass always has something
  /// to frost.
  final Color light;

  /// A third, low light near the floor.
  final Color mist;

  /// The translucent tint and edge of glass panes.
  final Color pane;
  final Color paneBorder;
  final Color shadow;

  /// Overdue dates, and nothing else.
  final Color overdue;

  /// The lit top edge of a pane.
  final Color edge;

  /// Priority 1 to 4, tuned for this brightness: the familiar red, orange,
  /// blue and grey, never the brand honey.
  final List<Color> priorities;
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

  /// Wool, terracotta, turquoise and midnight ink.
  static const weaving = FarashPalette(
    name: 'weaving',
    light: FarashColors(
      primary: Color(0xFF98503D),
      onPrimary: Colors.white,
      accent: Color(0xFF246D72),
      surface: Color(0xFFFAF5EB),
      onSurface: Color(0xFF283442),
      onSurfaceVariant: Color(0xFF69625B),
      selected: Color(0xFFF0DDD2),
      onSelected: Color(0xFF283442),
      backdrop: [Color(0xFFFAF5EB), Color(0xFFFAF5EB), Color(0xFFFAF5EB)],
      glow: Color(0xFFFAF5EB),
      light: Color(0xFFFAF5EB),
      mist: Color(0xFFFAF5EB),
      pane: Color(0xFFFFFBF3),
      paneBorder: Color(0x2469625B),
      shadow: Color(0x00000000),
      overdue: Color(0xFFB3263A),
      edge: Color(0x00FFFFFF),
      priorities: [
        Color(0xFFD23C4B),
        Color(0xFFC4670F),
        Color(0xFF3A63D0),
        Color(0xFF8B88A0),
      ],
    ),
    dark: FarashColors(
      primary: Color(0xFFF2B49A),
      onPrimary: Color(0xFF4C251B),
      accent: Color(0xFF86CCD0),
      surface: Color(0xFF19232F),
      onSurface: Color(0xFFF5EDE1),
      onSurfaceVariant: Color(0xFFCFC3B7),
      selected: Color(0xFF553B34),
      onSelected: Color(0xFFF5EDE1),
      backdrop: [Color(0xFF19232F), Color(0xFF19232F), Color(0xFF19232F)],
      glow: Color(0x0019232F),
      light: Color(0x0019232F),
      mist: Color(0x0019232F),
      pane: Color(0xFF24303D),
      paneBorder: Color(0x24A78D7F),
      shadow: Color(0x00000000),
      overdue: Color(0xFFFF9AA6),
      edge: Color(0x0024303D),
      priorities: [
        Color(0xFFFF8A9A),
        Color(0xFFFFB86B),
        Color(0xFF9FC2FF),
        Color(0xFF9A96B2),
      ],
    ),
  );
}

/// Hands the palette's glass colors to the backdrop and panes.
class FarashGlassColors extends ThemeExtension<FarashGlassColors> {
  const FarashGlassColors(this.colors);

  final FarashColors colors;

  static FarashColors of(BuildContext context) =>
      Theme.of(context).extension<FarashGlassColors>()?.colors ??
      FarashPalette.weaving.of(Theme.of(context).brightness);

  @override
  FarashGlassColors copyWith({FarashColors? colors}) =>
      FarashGlassColors(colors ?? this.colors);

  @override
  FarashGlassColors lerp(FarashGlassColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
