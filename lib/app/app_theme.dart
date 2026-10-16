import 'package:flutter/material.dart';
import 'package:farash/app/palette.dart';

abstract final class FarashTheme {
  /// The palette the app ships with.
  static const palette = FarashPalette.weaving;

  static const _controlRadius = 18.0;
  static const _surfaceRadius = 22.0;

  static ThemeData light([FarashPalette palette = FarashTheme.palette]) =>
      _build(Brightness.light, palette);

  static ThemeData dark([FarashPalette palette = FarashTheme.palette]) =>
      _build(Brightness.dark, palette);

  static ThemeData _build(Brightness brightness, FarashPalette palette) {
    final p = palette.of(brightness);
    // Warm tonal surfaces carry the woven identity across every screen.
    final generated = ColorScheme.fromSeed(
      seedColor: p.primary,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    final colors = generated.copyWith(
      primary: p.primary,
      secondary: p.accent,
      onSecondary: brightness == Brightness.dark
          ? const Color(0xFF123D42)
          : Colors.white,
      surfaceContainerLowest: brightness == Brightness.dark
          ? const Color(0xFF16202B)
          : const Color(0xFFFFFCF6),
      surfaceContainerLow: brightness == Brightness.dark
          ? const Color(0xFF22303D)
          : const Color(0xFFFFFAF2),
      surfaceContainer: brightness == Brightness.dark
          ? const Color(0xFF2A3744)
          : const Color(0xFFF1E7D9),
      surfaceContainerHigh: brightness == Brightness.dark
          ? const Color(0xFF33414E)
          : const Color(0xFFEADCCA),
      outlineVariant: brightness == Brightness.dark
          ? const Color(0xFF52606A)
          : const Color(0xFFDDCBB6),
      onPrimary: p.onPrimary,
      tertiary: p.accent,
      error: p.overdue,
      surface: p.surface,
      onSurface: p.onSurface,
      onSurfaceVariant: p.onSurfaceVariant,
      secondaryContainer: p.selected,
      onSecondaryContainer: p.onSelected,
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

    // One Persian type family keeps headings and task text coherent.
    TextStyle? naskh(TextStyle? style) => style?.copyWith(
      fontFamily: 'Vazirmatn',
      fontFamilyFallback: const ['Vazirmatn'],
      height: 1.35,
    );
    final text = base.textTheme.copyWith(
      displaySmall: naskh(base.textTheme.displaySmall),
      headlineLarge: naskh(base.textTheme.headlineLarge),
      headlineMedium: naskh(base.textTheme.headlineMedium),
      headlineSmall: naskh(base.textTheme.headlineSmall),
    );

    return base.copyWith(
      textTheme: text,
      extensions: [FarashGlassColors(p)],
      scaffoldBackgroundColor: colors.surface,
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          base.textTheme.labelMedium?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.w500,
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
      // Drawers and sheets sit over a scrim, where glass would frost only
      // the scrim; they are solid surfaces of the same night.
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.horizontal(
            end: Radius.circular(24),
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 48))),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: 0.2),
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
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 8, 0),
        titleTextStyle: base.textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w500,
        ),
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
      // Honey (primary) means "now" and the one primary action, so
      // secondary text actions and chip icons take the ink instead.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          iconColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        iconTheme: IconThemeData(color: colors.onSurfaceVariant, size: 18),
        selectedColor: colors.secondaryContainer,
        backgroundColor: colors.surfaceContainerLow,
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        checkmarkColor: colors.onSecondaryContainer,
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
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: controlShape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: controlShape,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }
}
