import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/pandora_tokens.dart';

/// The single structural boundary every Pandora route is built on.
///
/// It exists to make three owner-visible guarantees true by construction
/// rather than by each screen remembering to do the right thing:
///
/// 1. **Material ancestry.** Material-dependent controls such as
///    `DropdownButtonFormField` resolve a `Material` ancestor on every route,
///    including routes pushed outside the shell `Scaffold`. Without this, a
///    pushed page throws `No Material widget found`.
/// 2. **A deterministic opaque canvas.** The boundary paints the Porcelain or
///    Graphite canvas, so local translucency composites over a Pandora-owned
///    surface instead of the bare Android window, which is black in dark mode.
/// 3. **Cooperating system bars.** Status and navigation bar icon brightness
///    follows the effective theme, so edge-to-edge content stays legible after
///    a system theme change without a flash of the wrong treatment.
class PandoraRouteBoundary extends StatelessWidget {
  const PandoraRouteBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.pandoraPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iconBrightness = dark ? Brightness.light : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // The bars stay transparent so the canvas below shows through. The
        // canvas is opaque, so this never exposes the system window.
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Material(
        type: MaterialType.canvas,
        color: palette.canvas,
        child: child,
      ),
    );
  }
}
