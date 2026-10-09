import 'package:flutter/material.dart';

import '../design/pandora_theme.dart';
import '../design/pandora_tokens.dart';
import 'pandora_editorial_scope.dart';

/// PLP editorial theme for the Pandora owner workspace.
///
/// Installed once around the owner business surface. Owner pages inherit the
/// ivory canvas, ink, muted type, hairline dividers and serif titles. The
/// assistant stays outside this widget so its dark chat surface is unchanged.
/// The customer resort shell never mounts it.
class PandoraOwnerTheme extends StatelessWidget {
  const PandoraOwnerTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: pandoraOwnerTheme(Theme.of(context)),
        child: PandoraChrome(
          palette: PandoraChromePalette.plp,
          child: PandoraEditorialScope(
            editorial: true,
            child: ColoredBox(
              color: PandoraEditorialPalette.canvas,
              child: child,
            ),
          ),
        ),
      );
}

ThemeData pandoraOwnerTheme(ThemeData base) {
  final porcelain = PandoraTheme.porcelain;
  const canvas = PandoraEditorialPalette.canvas;
  const ink = PandoraEditorialPalette.ink;
  const muted = PandoraEditorialPalette.muted;
  const paper = PandoraEditorialPalette.paper;
  const line = PandoraEditorialPalette.line;
  const warm = PandoraEditorialPalette.warm;
  const accent = PandoraEditorialPalette.accent;
  final text = porcelain.textTheme.apply(bodyColor: ink, displayColor: ink);
  return porcelain.copyWith(
    platform: base.platform,
    visualDensity: base.visualDensity,
    scaffoldBackgroundColor: canvas,
    canvasColor: canvas,
    extensions: <ThemeExtension<dynamic>>[
      PandoraPalette.porcelain.copyWith(
        canvas: canvas,
        strongSurface: paper,
        subtleSurface: warm,
        outlineSoft: line,
      ),
    ],
    colorScheme: porcelain.colorScheme.copyWith(
      surface: paper,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: line,
      primary: accent,
      onPrimary: canvas,
      surfaceTint: Colors.transparent,
    ),
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(
        fontFamily: 'serif',
        fontSize: 16,
        letterSpacing: 2.6,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontFamily: 'serif',
        fontSize: 40,
        height: 0.98,
        fontWeight: FontWeight.w400,
        letterSpacing: -1.2,
        color: ink,
      ),
    ),
    iconTheme: const IconThemeData(color: ink),
    primaryIconTheme: const IconThemeData(color: ink),
    dividerColor: line,
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    cardTheme: porcelain.cardTheme.copyWith(
      color: paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: line),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    listTileTheme: const ListTileThemeData(iconColor: ink, textColor: ink),
    dialogTheme: const DialogThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
    ),
    chipTheme: porcelain.chipTheme.copyWith(
      backgroundColor: warm,
      selectedColor: ink,
      labelStyle: const TextStyle(color: ink),
      secondaryLabelStyle: const TextStyle(color: canvas),
      side: const BorderSide(color: line),
    ),
  );
}
