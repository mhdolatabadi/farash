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

  /// شیشهٔ شب (#49): night glass. A cool indigo room lit by two lights, a
  /// warm lamp that follows the project and a cool one across the room;
  /// panes of clear frosted glass float only where content passes beneath
  /// them. Honey means "now" and the one primary action.
  static const nightGlass = FarashPalette(
    name: 'nightGlass',
    light: FarashColors(
      primary: Color(0xFF8A5A12),
      onPrimary: Colors.white,
      accent: Color(0xFF3F6B52),
      surface: Color(0xFFF8F7FB),
      onSurface: Color(0xFF1B1E2C),
      onSurfaceVariant: Color(0xFF545A6D),
      selected: Color(0xFFE4E6F4),
      onSelected: Color(0xFF1B1E2C),
      backdrop: [Color(0xFFE8EBF6), Color(0xFFF3F2F4), Color(0xFFF1E9DD)],
      glow: Color(0x8CF2C27A),
      light: Color(0x738EA2F2),
      pane: Color(0x99FFFFFF),
      paneBorder: Color(0xE6FFFFFF),
      shadow: Color(0x1A1B1E2C),
      overdue: Color(0xFFB3343F),
      edge: Color(0xB3FFFFFF),
      priorities: [
        Color(0xFFC0392F),
        Color(0xFFB3600B),
        Color(0xFF2F5FC4),
        Color(0xFF7A7F90),
      ],
    ),
    dark: FarashColors(
      primary: Color(0xFFE8B66B),
      onPrimary: Color(0xFF21170A),
      accent: Color(0xFFA9C4B2),
      surface: Color(0xFF161B33),
      onSurface: Color(0xFFF1EEF6),
      onSurfaceVariant: Color(0xFFB4B6C8),
      selected: Color(0xFF2B3466),
      onSelected: Color(0xFFF1EEF6),
      backdrop: [Color(0xFF141A3D), Color(0xFF0D1129), Color(0xFF090C1D)],
      glow: Color(0x4DF0B868),
      light: Color(0x804A58D8),
      pane: Color(0x1FFFFFFF),
      paneBorder: Color(0x29FFFFFF),
      shadow: Color(0x66000000),
      overdue: Color(0xFFEF8C8F),
      edge: Color(0x24FFFFFF),
      priorities: [
        Color(0xFFF08A84),
        Color(0xFFF2A65A),
        Color(0xFF8DB1F2),
        Color(0xFF9096AE),
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
      FarashPalette.nightGlass.of(Theme.of(context).brightness);

  @override
  FarashGlassColors copyWith({FarashColors? colors}) =>
      FarashGlassColors(colors ?? this.colors);

  @override
  FarashGlassColors lerp(FarashGlassColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
