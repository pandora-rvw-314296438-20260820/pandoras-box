import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/design/pandora_theme.dart';
import 'package:pandora_mobile/core/design/pandora_tokens.dart';
import 'package:pandora_mobile/features/simple/pandora_v2_ui.dart';

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('graphite owner text meets WCAG AA contrast', () {
    expect(
      _contrast(
        PandoraColorTokens.graphiteText,
        PandoraColorTokens.graphiteSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(
        PandoraColorTokens.graphiteMuted,
        PandoraColorTokens.graphiteSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('porcelain owner text meets WCAG AA contrast', () {
    expect(
      _contrast(
        PandoraColorTokens.porcelainText,
        PandoraColorTokens.porcelainSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(
        PandoraColorTokens.porcelainMuted,
        PandoraColorTokens.porcelainSurface,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('routine action labels meet WCAG AA contrast', () {
    expect(
      _contrast(PandoraColorTokens.onAction, PandoraColorTokens.action),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(
        PandoraColorTokens.onActionLight,
        PandoraColorTokens.actionLight,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('the V2 surface aliases the canonical main-account tokens', () {
    expect(PandoraV2Colors.canvas, PandoraColorTokens.graphiteCanvas);
    expect(PandoraV2Colors.surface, PandoraColorTokens.graphiteSurface);
    expect(PandoraV2Colors.action, PandoraColorTokens.action);
  });

  test('mobile theme exposes the same semantic action color', () {
    expect(
        PandoraTheme.graphite.colorScheme.primary, PandoraColorTokens.action);
    expect(PandoraTheme.porcelain.colorScheme.primary,
        PandoraColorTokens.actionLight);
  });
}
