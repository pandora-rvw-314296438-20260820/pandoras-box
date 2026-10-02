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

  test('the released V2 surface keeps the approved true-black Obsidian palette', () {
    expect(PandoraV2Colors.canvas, const Color(0xFF000000));
    expect(PandoraV2Colors.surface, const Color(0xFF0A0A0A));
    expect(PandoraV2Colors.line, const Color(0xFF222222));
    expect(PandoraV2Colors.action, Colors.white);
    expect(PandoraV2Colors.onAction, Colors.black);
  });

  test('mobile theme exposes the same semantic action color', () {
    expect(
        PandoraTheme.graphite.colorScheme.primary, PandoraColorTokens.action);
    expect(PandoraTheme.porcelain.colorScheme.primary,
        PandoraColorTokens.actionLight);
  });
}
