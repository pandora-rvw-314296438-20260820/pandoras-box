import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_theme.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';
import 'package:pandora_mobile/core/widgets/pandora_route_boundary.dart';

import 'helpers/test_app.dart';

/// Background contract for Pandora Mobile.
///
/// An earlier revision required the root, page, and navigation surfaces to be
/// `Colors.transparent`. On a physical device that did not read as
/// transparency: it exposed the black Android window underlay behind every
/// translucent region. The contract is therefore stated in terms of the
/// owner-visible outcome rather than a literal colour value.
///
/// Transparency is still genuinely preserved — the brand mark keeps its alpha
/// and the navigation bar stays translucent. It simply composites over an
/// opaque, Pandora-owned canvas rather than the bare system window.
void main() {
  test('each theme paints an opaque, deterministic canvas', () {
    for (final theme in [PandoraTheme.porcelain, PandoraTheme.graphite]) {
      final canvas = theme.scaffoldBackgroundColor;
      expect(
        canvas.a,
        1.0,
        reason: 'A translucent scaffold exposes the Android window underlay.',
      );
      expect(canvas, isNot(Colors.transparent));
      expect(
        canvas,
        theme.extension<PandoraPalette>()!.canvas,
        reason: 'The scaffold must paint the canvas token exactly.',
      );
    }
  });

  test('neither canvas is pure black or pure white', () {
    expect(PandoraPalette.graphite.canvas, isNot(const Color(0xFF000000)));
    expect(PandoraPalette.porcelain.canvas, isNot(const Color(0xFFFFFFFF)));
  });

  test('the navigation bar stays translucent over the canvas', () {
    for (final theme in [PandoraTheme.porcelain, PandoraTheme.graphite]) {
      expect(theme.navigationBarTheme.backgroundColor, Colors.transparent);
    }
  });

  testWidgets('the route boundary paints the canvas opaquely', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        testApp(
          themeMode: mode,
          child: const PandoraRouteBoundary(child: SizedBox.expand()),
        ),
      );
      await tester.pump();

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(PandoraRouteBoundary),
              matching: find.byType(Material),
            )
            .first,
      );
      final expected = mode == ThemeMode.dark
          ? PandoraPalette.graphite.canvas
          : PandoraPalette.porcelain.canvas;
      expect(material.color, expected);
      expect(material.color!.a, 1.0);
    }
  });
}
