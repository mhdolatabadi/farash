import 'package:flutter/material.dart';

/// Every color the app's look depends on, for one brightness. Swapping a
/// palette restyles the whole app without touching widgets.
@immutable
class FarashColors {
  const FarashColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.containerLowest,
    required this.containerLow,
    required this.container,
    required this.containerHigh,
    required this.containerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.overdue,
    required this.priorities,
  });

  /// The one accent: primary actions, today, the running timer, selection.
  final Color primary;
  final Color onPrimary;

  /// Selected navigation, rows and chips.
  final Color primaryContainer;
  final Color onPrimaryContainer;

  /// Tomorrow and other near-future dates.
  final Color accent;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color containerLowest;
  final Color containerLow;
  final Color container;
  final Color containerHigh;
  final Color containerHighest;

  /// Field and control edges.
  final Color outline;

  /// Hairline dividers between rows.
  final Color outlineVariant;

  /// Overdue dates and errors, and nothing else.
  final Color overdue;

  /// Priority 1 to 4: the familiar red, orange, blue and grey.
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

  /// White and teal by day; near-black and lime by night.
  static const calm = FarashPalette(
    name: 'calm',
    light: FarashColors(
      primary: Color(0xFF0E7490),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFD9EEF2),
      onPrimaryContainer: Color(0xFF0B4F63),
      accent: Color(0xFF0757B5),
      surface: Colors.white,
      onSurface: Color(0xFF1B1F24),
      onSurfaceVariant: Color(0xFF5F6670),
      containerLowest: Colors.white,
      containerLow: Color(0xFFF6F7F9),
      container: Color(0xFFF0F2F4),
      containerHigh: Color(0xFFEAECEF),
      containerHighest: Color(0xFFE3E6EA),
      outline: Color(0xFFC9CED4),
      outlineVariant: Color(0xFFEEF0F2),
      overdue: Color(0xFFB42318),
      priorities: [
        Color(0xFFD1242F),
        Color(0xFFC2570C),
        Color(0xFF0969DA),
        Color(0xFF8C959F),
      ],
    ),
    dark: FarashColors(
      primary: Color(0xFFC8F25A),
      onPrimary: Color(0xFF0F1115),
      primaryContainer: Color(0xFF2E3A14),
      onPrimaryContainer: Color(0xFFDDF79A),
      accent: Color(0xFF74A7FF),
      surface: Color(0xFF0F1115),
      onSurface: Color(0xFFECEDEE),
      onSurfaceVariant: Color(0xFF9BA1A6),
      containerLowest: Color(0xFF0B0D10),
      containerLow: Color(0xFF15181D),
      container: Color(0xFF191C22),
      containerHigh: Color(0xFF20242B),
      containerHighest: Color(0xFF262A31),
      outline: Color(0xFF4A4F57),
      outlineVariant: Color(0xFF1E2127),
      overdue: Color(0xFFFF8A8A),
      priorities: [
        Color(0xFFFF6B6B),
        Color(0xFFFFA94D),
        Color(0xFF74A7FF),
        Color(0xFF8A9098),
      ],
    ),
  );
}

/// Hands the palette's extra colors, such as priorities, to widgets.
class FarashPaletteColors extends ThemeExtension<FarashPaletteColors> {
  const FarashPaletteColors(this.colors);

  final FarashColors colors;

  static FarashColors of(BuildContext context) =>
      Theme.of(context).extension<FarashPaletteColors>()?.colors ??
      FarashPalette.calm.of(Theme.of(context).brightness);

  @override
  FarashPaletteColors copyWith({FarashColors? colors}) =>
      FarashPaletteColors(colors ?? this.colors);

  @override
  FarashPaletteColors lerp(FarashPaletteColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
