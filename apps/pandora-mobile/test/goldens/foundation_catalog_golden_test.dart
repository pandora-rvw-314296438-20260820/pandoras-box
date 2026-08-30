import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/foundation_catalog.dart';
import '../helpers/test_app.dart';

void main() {
  // Exact pixels are reviewed on pinned Ubuntu CI. Windows font rasterization
  // is not byte-equivalent, while the cross-platform widget tests still cover
  // the same catalog semantics, geometry, themes, and text scaling.
  final pixelGoldenSkip = Platform.isWindows;

  Future<void> verifyCatalog(
    WidgetTester tester, {
    required Size size,
    required ThemeMode themeMode,
    required TextScaler textScaler,
    required String baseline,
  }) async {
    const catalogKey = ValueKey<String>('foundation-catalog');
    await setTestSurface(tester, logicalSize: size);
    await tester.pumpWidget(
      testApp(
        child: const RepaintBoundary(
          key: catalogKey,
          child: FoundationCatalog(),
        ),
        themeMode: themeMode,
        textScaler: textScaler,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(catalogKey),
      matchesGoldenFile('baselines/$baseline.png'),
    );
  }

  testWidgets('Porcelain 360x800', (tester) async {
    await verifyCatalog(
      tester,
      size: const Size(360, 800),
      themeMode: ThemeMode.light,
      textScaler: TextScaler.noScaling,
      baseline: 'foundation_porcelain_360x800',
    );
  }, skip: pixelGoldenSkip);

  testWidgets('Graphite 360x800', (tester) async {
    await verifyCatalog(
      tester,
      size: const Size(360, 800),
      themeMode: ThemeMode.dark,
      textScaler: TextScaler.noScaling,
      baseline: 'foundation_graphite_360x800',
    );
  }, skip: pixelGoldenSkip);

  testWidgets('Porcelain narrow 320x800', (tester) async {
    await verifyCatalog(
      tester,
      size: const Size(320, 800),
      themeMode: ThemeMode.light,
      textScaler: TextScaler.noScaling,
      baseline: 'foundation_porcelain_320x800',
    );
  }, skip: pixelGoldenSkip);

  testWidgets('Porcelain 2x text', (tester) async {
    await verifyCatalog(
      tester,
      size: const Size(360, 800),
      themeMode: ThemeMode.light,
      textScaler: TextScaler.linear(2),
      baseline: 'foundation_porcelain_2x_text',
    );
  }, skip: pixelGoldenSkip);
}
