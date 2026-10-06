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
    required this.relief,
    required this.reliefShade,
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

  /// Overdue dates, and nothing else.
  final Color overdue;

  /// The pressed-pebble pattern of the glass: a lit and a shaded side.
  final Color relief;
  final Color reliefShade;
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

  /// شیشهٔ مشجر (#47): patterned privacy glass at night. Indigo night in
  /// front, honey lamplight behind; honey means only "now", sage marks
  /// tomorrow and pomegranate marks overdue. Night is the designed default,
  /// day the same door by daylight.
  static const moshajjar = FarashPalette(
    name: 'moshajjar',
    light: FarashColors(
      primary: Color(0xFF8A5A12),
      onPrimary: Colors.white,
      accent: Color(0xFF3F6B52),
      surface: Color(0xFFFBF8F2),
      onSurface: Color(0xFF1E2230),
      onSurfaceVariant: Color(0xFF5A5E6B),
      selected: Color(0xFFEDE5D5),
      onSelected: Color(0xFF1E2230),
      backdrop: [Color(0xFFE9ECF3), Color(0xFFF6F2EA), Color(0xFFEFE3CF)],
      glow: Color(0x73F0C27A),
      pane: Color(0x99FFFFFF),
      paneBorder: Color(0xD9FFFFFF),
      shadow: Color(0x141E2230),
      overdue: Color(0xFFB3343F),
      relief: Color(0x0FFFFFFF),
      reliefShade: Color(0x081E2230),
    ),
    dark: FarashColors(
      primary: Color(0xFFE8B66B),
      onPrimary: Color(0xFF21170A),
      accent: Color(0xFFA9C4B2),
      surface: Color(0xFF141B36),
      onSurface: Color(0xFFF3ECE2),
      onSurfaceVariant: Color(0xFFB9B2A6),
      selected: Color(0xFF26305A),
      onSelected: Color(0xFFF3ECE2),
      backdrop: [Color(0xFF17204A), Color(0xFF0F1530), Color(0xFF0A0E1F)],
      glow: Color(0x52E8B66B),
      pane: Color(0x0FE8E4F0),
      paneBorder: Color(0x26FFECCE),
      shadow: Color(0x59000000),
      overdue: Color(0xFFEF8C8F),
      relief: Color(0x08FFF4E2),
      reliefShade: Color(0x12000000),
    ),
  );
}

/// Hands the palette's glass colors to the backdrop and panes.
class FarashGlassColors extends ThemeExtension<FarashGlassColors> {
  const FarashGlassColors(this.colors);

  final FarashColors colors;

  static FarashColors of(BuildContext context) =>
      Theme.of(context).extension<FarashGlassColors>()?.colors ??
      FarashPalette.moshajjar.of(Theme.of(context).brightness);

  @override
  FarashGlassColors copyWith({FarashColors? colors}) =>
      FarashGlassColors(colors ?? this.colors);

  @override
  FarashGlassColors lerp(FarashGlassColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
