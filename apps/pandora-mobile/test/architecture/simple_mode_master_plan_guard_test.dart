import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Simple Mode keeps the canonical four-layer safety board', () {
    final source = File(
      'lib/features/simple/simple_safety_screen.dart',
    ).readAsStringSync();

    for (final label in const [
      'Identity & Access',
      'Approval & Execution',
      'Source Authority',
      'Runtime & Secrets',
      'Healthy',
      'Needs attention',
      'Blocked',
      'Not checked',
      'Not applicable',
    ]) {
      expect(source, contains(label));
    }
    expect(source, contains('No aggregate score'));
    expect(source, isNot(contains('security score')));
  });

  test('Simple Mode uses rail navigation on large screens', () {
    final source = File('lib/app/pandora_shell.dart').readAsStringSync();
    expect(source, contains('constraints.maxWidth >= 900'));
    expect(source, contains('NavigationRail('));
    expect(source, contains('_PandoraBottomBar('));
  });

  test('professional safety diagnostics remain behind More', () {
    final source = File(
      'lib/features/simple/more_screen.dart',
    ).readAsStringSync();
    expect(source, contains('const SimpleSafetyScreen()'));
    expect(source, contains("title: 'Safety diagnostics'"));
    expect(source, contains('const SafetyScreen()'));
  });
}
