import 'package:flutter/material.dart';

import 'pandora_tokens.dart';

abstract final class PandoraTheme {
  static const Color _primary = Color(0xFF4D55C7);

  /// Warm neutral premium canvas rather than sterile pure white.
  static ThemeData get porcelain => _build(
        brightness: Brightness.light,
        palette: PandoraPalette.porcelain,
        background: PandoraPalette.porcelain.canvas,
        surface: const Color(0xFFFFFFFF),
      );

  /// Premium charcoal rather than pure black or the bare Android underlay.
  static ThemeData get graphite => _build(
        brightness: Brightness.dark,
        palette: PandoraPalette.graphite,
        background: PandoraPalette.graphite.canvas,
        surface: const Color(0xFF17181D),
      );

  static ThemeData _build({
    required Brightness brightness,
    required PandoraPalette palette,
    required Color background,
    required Color surface,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: brightness,
      surface: surface,
      error: palette.critical,
    );
    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[palette],
    );
    final textTheme = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8, // Slightly more tracked
        height: 1.1,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.2,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600, // Slightly less bold title
        letterSpacing: -0.1,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.55), // Improved readability
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.55),
      bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.45),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return base.copyWith(
      textTheme: textTheme,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: palette.strongSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: PandoraRadius.cardBorder,
          side: BorderSide(color: palette.outlineSoft),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        selectedLabelTextStyle: textTheme.labelLarge,
        unselectedLabelTextStyle: textTheme.labelLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.strongSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PandoraSpacing.md,
          vertical: PandoraSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: PandoraRadius.controlBorder,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: PandoraRadius.controlBorder,
          borderSide: BorderSide(color: palette.outlineSoft),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, PandoraSize.minimumTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: PandoraRadius.controlBorder,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: PandoraSpacing.lg,
            vertical: PandoraSpacing.sm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, PandoraSize.minimumTouchTarget),
          shape: const RoundedRectangleBorder(
            borderRadius: PandoraRadius.controlBorder,
          ),
          side: BorderSide(color: palette.outlineSoft),
          padding: const EdgeInsets.symmetric(
            horizontal: PandoraSpacing.lg,
            vertical: PandoraSpacing.sm,
          ),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(
            Size.square(PandoraSize.minimumTouchTarget),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.outlineSoft,
        thickness: 1,
        space: PandoraSpacing.xl,
      ),
    );
  }
}
