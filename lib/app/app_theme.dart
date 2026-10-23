import 'package:flutter/material.dart';
import 'package:farash/app/palette.dart';

abstract final class FarashTheme {
  /// The palette the app ships with.
  static const palette = FarashPalette.calm;

  static const _fieldRadius = 12.0;
  static const _surfaceRadius = 16.0;

  static ThemeData light([FarashPalette palette = FarashTheme.palette]) =>
      _build(Brightness.light, palette);

  static ThemeData dark([FarashPalette palette = FarashTheme.palette]) =>
      _build(Brightness.dark, palette);

  static ThemeData _build(Brightness brightness, FarashPalette palette) {
    final p = palette.of(brightness);
    // Material 3 roles, set explicitly so one accent carries the app and
    // every surface stays neutral.
    final colors =
        ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: brightness,
        ).copyWith(
          primary: p.primary,
          onPrimary: p.onPrimary,
          primaryContainer: p.primaryContainer,
          onPrimaryContainer: p.onPrimaryContainer,
          secondary: p.primary,
          onSecondary: p.onPrimary,
          secondaryContainer: p.primaryContainer,
          onSecondaryContainer: p.onPrimaryContainer,
          tertiary: p.accent,
          error: p.overdue,
          surface: p.surface,
          onSurface: p.onSurface,
          onSurfaceVariant: p.onSurfaceVariant,
          surfaceContainerLowest: p.containerLowest,
          surfaceContainerLow: p.containerLow,
          surfaceContainer: p.container,
          surfaceContainerHigh: p.containerHigh,
          surfaceContainerHighest: p.containerHighest,
          surfaceTint: Colors.transparent,
          outline: p.outline,
          outlineVariant: p.outlineVariant,
        );
    final base = ThemeData(
      brightness: brightness,
      colorScheme: colors,
      fontFamily: 'Vazirmatn',
      useMaterial3: true,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: BorderSide(color: colors.outline),
    );
    const stadium = StadiumBorder();

    return base.copyWith(
      extensions: [FarashPaletteColors(p)],
      scaffoldBackgroundColor: colors.surface,
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        elevation: 0,
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.onSurface
                : colors.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
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
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: 0.25),
        selectionHandleColor: colors.primary,
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
        minTileHeight: 52,
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 0),
        titleTextStyle: base.textTheme.bodyLarge?.copyWith(
          color: colors.onSurface,
        ),
        shape: stadium,
        iconColor: colors.onSurfaceVariant,
        selectedColor: colors.onPrimaryContainer,
        selectedTileColor: colors.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: const WidgetStatePropertyAll(stadium),
          textStyle: WidgetStatePropertyAll(
            base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      // The accent means the one primary action; other text actions take
      // the ink.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          iconColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
          shape: const WidgetStatePropertyAll(stadium),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: colors.outline)),
          shape: const WidgetStatePropertyAll(stadium),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 18),
        selectedColor: colors.primaryContainer,
        backgroundColor: colors.surface,
        side: BorderSide(color: colors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        checkmarkColor: colors.onPrimaryContainer,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
          side: WidgetStatePropertyAll(BorderSide(color: colors.outline)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.primary,
        linearTrackColor: colors.surfaceContainerHighest,
        circularTrackColor: colors.surfaceContainerHighest,
      ),
    );
  }
}
