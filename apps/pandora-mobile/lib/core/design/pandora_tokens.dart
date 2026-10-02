import 'package:flutter/material.dart';

/// Shared semantic colours for every Pandora owner/operator surface.
///
/// Product red is deliberately limited to brand identity and critical states.
/// Routine actions use [action] so colour meaning remains consistent.
abstract final class PandoraColorTokens {
  static const brand = Color(0xFFEF4349);
  // Warm neutral Pandora action colours. Keep Material controls out of the
  // old indigo family so dialogs, menus and selection states stay on-brand.
  static const action = Color(0xFFE8E1D5);
  static const actionHover = Color(0xFFF7F2E9);
  static const onAction = Color(0xFF17140F);
  static const actionLight = Color(0xFF24211D);
  static const onActionLight = Color(0xFFFFFFFF);

  static const graphiteCanvas = Color(0xFF101116);
  static const graphiteSurface = Color(0xFF191B22);
  static const graphiteSurfaceSoft = Color(0xFF20232B);
  static const graphiteText = Color(0xFFF7F7F8);
  static const graphiteMuted = Color(0xFFB3B6C0);
  static const graphiteOutline = Color(0xFF30333D);

  static const porcelainCanvas = Color(0xFFF6F5F2);
  static const porcelainSurface = Color(0xFFFFFFFF);
  static const porcelainSurfaceSoft = Color(0xFFF0F0F4);
  static const porcelainText = Color(0xFF17181D);
  static const porcelainMuted = Color(0xFF5F636D);
  static const porcelainOutline = Color(0xFFD9DAE2);

  static const verifiedDark = Color(0xFF67D7A3);
  static const attentionDark = Color(0xFFFFC46B);
  static const criticalDark = Color(0xFFFF817A);
}

abstract final class PandoraSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double display = 48;
}

abstract final class PandoraRadius {
  static const double control = 12;
  static const double card = 18;
  static const double prominent = 24;

  static const BorderRadius controlBorder = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius prominentBorder = BorderRadius.all(
    Radius.circular(prominent),
  );
}

abstract final class PandoraSize {
  static const double minimumTouchTarget = 48;
  static const double compactMark = 44;
  static const double signInMark = 112;
  static const double contentMaxWidth = 720;
  static const double wideBreakpoint = 840;
}

abstract final class PandoraMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);
}

abstract final class PandoraElevation {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}

@immutable
class PandoraPalette extends ThemeExtension<PandoraPalette> {
  const PandoraPalette({
    required this.canvas,
    required this.verified,
    required this.onVerified,
    required this.attention,
    required this.onAttention,
    required this.critical,
    required this.onCritical,
    required this.informative,
    required this.onInformative,
    required this.subtleSurface,
    required this.strongSurface,
    required this.outlineSoft,
  });

  /// The deterministic, always-opaque application canvas.
  ///
  /// Every Pandora route paints this colour before any local translucency is
  /// composited on top of it. It is the single guarantee that the owner never
  /// sees the bare Android window underlay, which is black in dark mode. The
  /// native window background is kept byte-identical to these values so cold
  /// start, warm start, resume, and system theme changes stay continuous.
  final Color canvas;

  final Color verified;
  final Color onVerified;
  final Color attention;
  final Color onAttention;
  final Color critical;
  final Color onCritical;
  final Color informative;
  final Color onInformative;
  final Color subtleSurface;
  final Color strongSurface;
  final Color outlineSoft;

  static const porcelain = PandoraPalette(
    canvas: PandoraColorTokens.porcelainCanvas,
    verified: Color(0xFF0B6B45),
    onVerified: Color(0xFFFFFFFF),
    attention: Color(0xFF9A5A00),
    onAttention: Color(0xFFFFFFFF),
    critical: Color(0xFFB3261E),
    onCritical: Color(0xFFFFFFFF),
    informative: Color(0xFF465047),
    onInformative: Color(0xFFFFFFFF),
    subtleSurface: PandoraColorTokens.porcelainSurfaceSoft,
    strongSurface: PandoraColorTokens.porcelainSurface,
    outlineSoft: PandoraColorTokens.porcelainOutline,
  );

  static const graphite = PandoraPalette(
    canvas: PandoraColorTokens.graphiteCanvas,
    verified: PandoraColorTokens.verifiedDark,
    onVerified: Color(0xFF052216),
    attention: PandoraColorTokens.attentionDark,
    onAttention: Color(0xFF2A1700),
    critical: PandoraColorTokens.criticalDark,
    onCritical: Color(0xFF690005),
    informative: Color(0xFFD8C7A4),
    onInformative: Color(0xFF2A2115),
    subtleSurface: PandoraColorTokens.graphiteSurfaceSoft,
    strongSurface: PandoraColorTokens.graphiteSurface,
    outlineSoft: PandoraColorTokens.graphiteOutline,
  );

  @override
  PandoraPalette copyWith({
    Color? canvas,
    Color? verified,
    Color? onVerified,
    Color? attention,
    Color? onAttention,
    Color? critical,
    Color? onCritical,
    Color? informative,
    Color? onInformative,
    Color? subtleSurface,
    Color? strongSurface,
    Color? outlineSoft,
  }) =>
      PandoraPalette(
        canvas: canvas ?? this.canvas,
        verified: verified ?? this.verified,
        onVerified: onVerified ?? this.onVerified,
        attention: attention ?? this.attention,
        onAttention: onAttention ?? this.onAttention,
        critical: critical ?? this.critical,
        onCritical: onCritical ?? this.onCritical,
        informative: informative ?? this.informative,
        onInformative: onInformative ?? this.onInformative,
        subtleSurface: subtleSurface ?? this.subtleSurface,
        strongSurface: strongSurface ?? this.strongSurface,
        outlineSoft: outlineSoft ?? this.outlineSoft,
      );

  @override
  PandoraPalette lerp(ThemeExtension<PandoraPalette>? other, double t) {
    if (other is! PandoraPalette) return this;
    return PandoraPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      verified: Color.lerp(verified, other.verified, t)!,
      onVerified: Color.lerp(onVerified, other.onVerified, t)!,
      attention: Color.lerp(attention, other.attention, t)!,
      onAttention: Color.lerp(onAttention, other.onAttention, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
      onCritical: Color.lerp(onCritical, other.onCritical, t)!,
      informative: Color.lerp(informative, other.informative, t)!,
      onInformative: Color.lerp(onInformative, other.onInformative, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      strongSurface: Color.lerp(strongSurface, other.strongSurface, t)!,
      outlineSoft: Color.lerp(outlineSoft, other.outlineSoft, t)!,
    );
  }
}

extension PandoraThemeContext on BuildContext {
  PandoraPalette get pandoraPalette =>
      Theme.of(this).extension<PandoraPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? PandoraPalette.graphite
          : PandoraPalette.porcelain);
}
