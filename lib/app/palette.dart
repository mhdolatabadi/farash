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

  /// شبنم (#49): dew on glass. Peach, lavender and mint light behind white
  /// frosted glass by day, and the same hues low in a violet night. Violet
  /// means "now" and the one primary action; mint marks tomorrow and rose
  /// marks overdue.
  static const dew = FarashPalette(
    name: 'dew',
    light: FarashColors(
      primary: Color(0xFF5B45D6),
      onPrimary: Colors.white,
      accent: Color(0xFF1F7A5C),
      surface: Color(0xFFFBFAFE),
      onSurface: Color(0xFF1D1B2E),
      onSurfaceVariant: Color(0xFF5D5A73),
      selected: Color(0xFFECE7FF),
      onSelected: Color(0xFF1D1B2E),
      backdrop: [Color(0xFFF7F3FB), Color(0xFFF4F1F8), Color(0xFFF3F1F8)],
      glow: Color(0xFFFFD9C2),
      light: Color(0xFFD9D2FF),
      mist: Color(0xFFC9F0E4),
      pane: Color(0x9EFFFFFF),
      paneBorder: Color(0xF2FFFFFF),
      shadow: Color(0x14503C8C),
      overdue: Color(0xFFB3263A),
      edge: Color(0xCCFFFFFF),
      priorities: [
        Color(0xFFD23C4B),
        Color(0xFFC4670F),
        Color(0xFF3A63D0),
        Color(0xFF8B88A0),
      ],
    ),
    dark: FarashColors(
      primary: Color(0xFFB4A7FF),
      onPrimary: Color(0xFF1B1340),
      accent: Color(0xFF8FD9BF),
      surface: Color(0xFF1C1834),
      onSurface: Color(0xFFF1EEFA),
      onSurfaceVariant: Color(0xFFB9B4CF),
      selected: Color(0xFF332C66),
      onSelected: Color(0xFFF1EEFA),
      backdrop: [Color(0xFF1C1736), Color(0xFF15122B), Color(0xFF0F0D20)],
      glow: Color(0x38FF9EB5),
      light: Color(0x599682FF),
      mist: Color(0x386ED2B4),
      pane: Color(0x1AFFFFFF),
      paneBorder: Color(0x24FFFFFF),
      shadow: Color(0x59000000),
      overdue: Color(0xFFFF9AA6),
      edge: Color(0x1FFFFFFF),
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
      FarashPalette.dew.of(Theme.of(context).brightness);

  @override
  FarashGlassColors copyWith({FarashColors? colors}) =>
      FarashGlassColors(colors ?? this.colors);

  @override
  FarashGlassColors lerp(FarashGlassColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
