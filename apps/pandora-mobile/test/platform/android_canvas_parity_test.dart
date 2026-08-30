import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';

/// The Android window underlay and the Flutter canvas must agree exactly.
///
/// If they drift, the owner sees a seam at cold start, at resume, or behind any
/// translucent region — which is the P0.2 black-underlay defect.
void main() {
  String canvasResource(String valuesDir) {
    final file = File(
      'platform/android/app/src/main/res/$valuesDir/colors.xml',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Missing Android canvas resource for $valuesDir.',
    );
    final match = RegExp(
      r'<color name="pandora_canvas">#([0-9A-Fa-f]{8})</color>',
    ).firstMatch(file.readAsStringSync());
    expect(
      match,
      isNotNull,
      reason: 'pandora_canvas is not declared as an 8-digit ARGB value.',
    );
    return match!.group(1)!.toUpperCase();
  }

  String argb(Color color) => (color.toARGB32() & 0xFFFFFFFF)
      .toRadixString(16)
      .padLeft(8, '0')
      .toUpperCase();

  test('Porcelain window underlay matches the Flutter canvas', () {
    expect(canvasResource('values'), argb(PandoraPalette.porcelain.canvas));
  });

  test('Graphite window underlay matches the Flutter canvas', () {
    expect(
      canvasResource('values-night'),
      argb(PandoraPalette.graphite.canvas),
    );
  });

  test('Graphite canvas is premium charcoal rather than pure black', () {
    expect(argb(PandoraPalette.graphite.canvas), isNot('FF000000'));
  });

  // Only the effective declarations are asserted. XML comments in these files
  // legitimately name the platform defaults they exist to override.
  String declarations(String path) =>
      File(path)
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('the splash never hardcodes platform white', () {
    for (final dir in const ['drawable', 'drawable-night']) {
      final file = File(
        'platform/android/app/src/main/res/$dir/launch_background.xml',
      );
      expect(file.existsSync(), isTrue, reason: 'Missing $dir splash.');
      final contents = declarations(file.path);
      expect(contents, contains('@color/pandora_canvas'));
      expect(contents, isNot(contains('@android:color/white')));
    }
  });

  test('the window background is never the platform default', () {
    for (final dir in const ['values', 'values-night']) {
      final contents = declarations(
        'platform/android/app/src/main/res/$dir/styles.xml',
      );
      expect(contents, isNot(contains('?android:colorBackground')));
      expect(contents, contains('@color/pandora_canvas'));
    }
  });
}
