import 'package:flutter/material.dart';

/// Every color the app's look depends on, for one brightness. Swapping a
/// palette restyles the whole app without touching widgets.
@immutable
class MenvalColors {
  const MenvalColors({
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
    required this.softGround,
    required this.softLight,
    required this.softShade,
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

  /// The ground under raised tiles and inset wells on the main
  /// destinations, and the two shadows that lift or sink them.
  final Color softGround;
  final Color softLight;
  final Color softShade;
}

@immutable
class MenvalPalette {
  const MenvalPalette({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final MenvalColors light;
  final MenvalColors dark;

  MenvalColors of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Approved tactile stone/charcoal surfaces: restrained in light mode,
  /// with only one warm primary action accent in dark mode.
  static const stone = MenvalPalette(
    name: 'stone',
    light: MenvalColors(
      primary: Color(0xFF383936),
      onPrimary: Color(0xFFF8F6F3),
      primaryContainer: Color(0xFFE7E4E0),
      onPrimaryContainer: Color(0xFF282925),
      accent: Color(0xFF555650),
      surface: Color(0xFFF9F7F5),
      onSurface: Color(0xFF252623),
      onSurfaceVariant: Color(0xFF63645F),
      containerLowest: Color(0xFFFFFFFF),
      containerLow: Color(0xFFF5F2EF),
      container: Color(0xFFF0EDEA),
      containerHigh: Color(0xFFEAE7E3),
      containerHighest: Color(0xFFE3DFDB),
      outline: Color(0xFFA7A49F),
      outlineVariant: Color(0xFFD9D5D0),
      overdue: Color(0xFFA3544C),
      priorities: [
        Color(0xFFA3544C),
        Color(0xFF8F7861),
        Color(0xFF636763),
        Color(0xFF747570),
      ],
      softGround: Color(0xFFF2EFEC),
      softLight: Color(0xFFFFFFFF),
      softShade: Color(0xFFD0CBC6),
    ),
    dark: MenvalColors(
      primary: Color(0xFFE8C487),
      onPrimary: Color(0xFF22242A),
      primaryContainer: Color(0xFF4A4034),
      onPrimaryContainer: Color(0xFFF0D39D),
      accent: Color(0xFFC5A875),
      surface: Color(0xFF292C34),
      onSurface: Color(0xFFF0EEE9),
      onSurfaceVariant: Color(0xFFAAA8A5),
      containerLowest: Color(0xFF1C1F25),
      containerLow: Color(0xFF24272E),
      container: Color(0xFF2C3038),
      containerHigh: Color(0xFF333740),
      containerHighest: Color(0xFF3B4049),
      outline: Color(0xFF686B73),
      outlineVariant: Color(0xFF42464E),
      overdue: Color(0xFFE49B8F),
      priorities: [
        Color(0xFFE49B8F),
        Color(0xFFD2B082),
        Color(0xFFAAAEB4),
        Color(0xFF747981),
      ],
      softGround: Color(0xFF252830),
      softLight: Color(0xFF363A43),
      softShade: Color(0xFF14161B),
    ),
  );

  /// White and teal by day; near-black and lime by night.
  static const calm = MenvalPalette(
    name: 'calm',
    light: MenvalColors(
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
      outline: Color(0xFF878E97),
      outlineVariant: Color(0xFFE3E6EA),
      overdue: Color(0xFFB42318),
      priorities: [
        Color(0xFFD1242F),
        Color(0xFFC2570C),
        Color(0xFF0969DA),
        Color(0xFF737B85),
      ],
      softGround: Color(0xFFE9EDF1),
      softLight: Color(0xFFFFFFFF),
      softShade: Color(0xFFC9D0D7),
    ),
    dark: MenvalColors(
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
      outline: Color(0xFF6B717A),
      outlineVariant: Color(0xFF262A31),
      overdue: Color(0xFFFF8A8A),
      priorities: [
        Color(0xFFFF6B6B),
        Color(0xFFFFA94D),
        Color(0xFF74A7FF),
        Color(0xFF8A9098),
      ],
      softGround: Color(0xFF16191E),
      softLight: Color(0xFF22262D),
      softShade: Color(0xFF0A0C0F),
    ),
  );
}

/// Hands the palette's extra colors, such as priorities, to widgets.
class MenvalPaletteColors extends ThemeExtension<MenvalPaletteColors> {
  const MenvalPaletteColors(this.colors);

  final MenvalColors colors;

  static MenvalColors of(BuildContext context) =>
      Theme.of(context).extension<MenvalPaletteColors>()?.colors ??
      MenvalPalette.stone.of(Theme.of(context).brightness);

  @override
  MenvalPaletteColors copyWith({MenvalColors? colors}) =>
      MenvalPaletteColors(colors ?? this.colors);

  @override
  MenvalPaletteColors lerp(MenvalPaletteColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
