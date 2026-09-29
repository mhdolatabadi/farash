import 'package:flutter/material.dart';

abstract final class FarashTheme {
  /// Brand color: a deep teal, the check on the app icon.
  static const seed = Color(0xFF0F8B7C);

  static const _controlRadius = 12.0;
  static const _surfaceRadius = 16.0;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colors = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final base = ThemeData(
      brightness: brightness,
      colorScheme: colors,
      fontFamily: 'Vazirmatn',
      useMaterial3: true,
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
    );
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_controlRadius),
      borderSide: BorderSide(color: colors.outlineVariant),
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_surfaceRadius),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: controlShape,
        iconColor: colors.onSurfaceVariant,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: outline.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: WidgetStatePropertyAll(controlShape),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
