import 'package:flutter/material.dart';

/// Turns on the locked PLP ivory treatment for Pandora owner pages.
///
/// Absent or `editorial: false` leaves the existing dark Pandora surfaces
/// unchanged. Customer resort pages do not read this scope.
class PandoraEditorialScope extends InheritedWidget {
  const PandoraEditorialScope({
    required this.editorial,
    required super.child,
  });

  final bool editorial;

  static bool active(BuildContext context) =>
      context
              .dependOnInheritedWidgetOfExactType<PandoraEditorialScope>()
              ?.editorial ==
          true ||
      (context
              .dependOnInheritedWidgetOfExactType<PandoraChrome>()
              ?.palette
              .editorial ??
          false);

  @override
  bool updateShouldNotify(PandoraEditorialScope oldWidget) =>
      editorial != oldWidget.editorial;
}

/// The PLP Enterprise canvas. Kept here so owner chrome can match the resort
/// pages without importing the resort feature library.
abstract final class PandoraEditorialPalette {
  static const canvas = Color(0xFFFAF8F3);
  static const paper = Color(0xFFFFFDFC);
  static const warm = Color(0xFFF2EEE6);
  static const ink = Color(0xFF171512);
  static const muted = Color(0xFF746F67);
  static const line = Color(0xFFE1DBD1);
  static const accent = Color(0xFF70643F);
}

/// Palette installed once by [PandoraOwnerTheme]. Owner pages read these roles.
/// There is no per-widget editorial branch: the shell chooses the palette.
class PandoraChromePalette {
  const PandoraChromePalette({
    required this.editorial,
    required this.canvas,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.line,
    required this.pill,
    required this.accent,
    required this.warm,
  });

  final bool editorial;
  final Color canvas;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color line;
  final Color pill;
  final Color accent;
  final Color warm;

  /// Dark owner console. Matches the pre-PLP core screen, not a second theme.
  static const dark = PandoraChromePalette(
    editorial: false,
    canvas: Color(0xFF090B0E),
    paper: Color(0xFF121519),
    ink: Color(0xFFF2F2F2),
    muted: Color(0xFFA0A3A8),
    line: Color(0xFF292D32),
    pill: Color(0xFF23272D),
    accent: Color(0xFFAAA39A),
    warm: Color(0xFF18140E),
  );

  static const plp = PandoraChromePalette(
    editorial: true,
    canvas: PandoraEditorialPalette.canvas,
    paper: PandoraEditorialPalette.paper,
    ink: PandoraEditorialPalette.ink,
    muted: PandoraEditorialPalette.muted,
    line: PandoraEditorialPalette.line,
    pill: Color(0xFFE7E1D6),
    accent: PandoraEditorialPalette.accent,
    warm: PandoraEditorialPalette.warm,
  );

  TextStyle get contextTitle => editorial
      ? const TextStyle(
          color: PandoraEditorialPalette.ink,
          fontFamily: 'serif',
          fontSize: 16,
          letterSpacing: 2.6,
          fontWeight: FontWeight.w400,
        )
      : const TextStyle(
          color: Color(0xFFF2F2F2),
          fontSize: 20,
          fontWeight: FontWeight.w700,
        );

  TextStyle get sectionTitle => editorial
      ? const TextStyle(
          color: PandoraEditorialPalette.ink,
          fontFamily: 'serif',
          fontSize: 29,
          height: 1.02,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.5,
        )
      : const TextStyle(
          color: Color(0xFFF2F2F2),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        );

  TextStyle get recordTitle => editorial
      ? const TextStyle(
          color: PandoraEditorialPalette.ink,
          fontFamily: 'serif',
          fontSize: 20,
          height: 1.05,
          fontWeight: FontWeight.w400,
        )
      : const TextStyle(
          color: Color(0xFFF2F2F2),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        );
}

class PandoraChrome extends InheritedWidget {
  const PandoraChrome({required this.palette, required super.child});

  final PandoraChromePalette palette;

  static PandoraChromePalette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PandoraChrome>()?.palette ??
      PandoraChromePalette.dark;

  @override
  bool updateShouldNotify(PandoraChrome oldWidget) =>
      palette.editorial != oldWidget.palette.editorial ||
      palette.canvas != oldWidget.palette.canvas;
}

/// Maps a dark Pandora color onto the PLP palette while owner mode is on.
/// Unknown colors, including status red and green, stay as they are.
Color pandoraOwnerColor(BuildContext context, Color color) {
  if (!PandoraEditorialScope.active(context)) return color;
  final installed =
      context.dependOnInheritedWidgetOfExactType<PandoraChrome>()?.palette;
  final palette = installed != null && installed.editorial
      ? installed
      : PandoraChromePalette.plp;
  return switch (color.toARGB32()) {
    0xFF000000 || 0xFF090B0E => palette.canvas,
    0xFF0A0A0A ||
    0xFF10141A ||
    0xFF141414 ||
    0xFF121519 ||
    0xFF181010 ||
    0xFF101814 ||
    0xFF151018 ||
    0xFF18140E =>
      palette.paper,
    0xFF222222 || 0xFF23272D || 0xFF292D32 => palette.line,
    0xFFFFFFFF || 0xFFD8D8D8 || 0xFFF2F2F2 => palette.ink,
    0xFF888888 || 0xFFA0A3A8 || 0xFFAAA39A => palette.muted,
    0xFF7EA8F6 || 0xFFB69AE8 => palette.accent,
    _ => color,
  };
}

class PandoraEditorialTitle extends StatelessWidget {
  const PandoraEditorialTitle(
    this.title, {
    super.key,
    this.align = TextAlign.start,
  });

  final String title;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: PandoraChrome.of(context).contextTitle,
      );
}
