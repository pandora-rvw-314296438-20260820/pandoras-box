import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Simple Mode primary navigation is project-first and owner-safe', () {
    final shell = File('lib/app/pandora_shell.dart').readAsStringSync();
    for (final label in const [
      "label: 'Home'",
      "label: 'Projects'",
      "label: 'Ask Pandora'",
      "label: 'Needs You'",
      "label: 'Business'",
    ]) {
      expect(shell, contains(label));
    }
    expect(shell, isNot(contains("label: 'Systems'")));
    expect(shell, isNot(contains("label: 'More'")));
  });

  test('Build Theatre never advances from a presentation timer', () {
    final source =
        File('lib/features/simple/project_journey_flow.dart').readAsStringSync();
    expect(source, contains('runtime.runtime(widget.project.id)'));
    expect(source, contains('didChangeAppLifecycleState'));
    expect(source, contains('AppLifecycleState.resumed'));
    expect(source, contains('Timer.periodic(const Duration(seconds: 2)'));
    expect(source, isNot(contains('Duration(milliseconds: 1200)')));
    expect(source, isNot(contains('_stage += 1')));
  });

  test('Build Theatre keeps the Pandora signature composition', () {
    final source =
        File('lib/features/simple/project_journey_flow.dart').readAsStringSync();
    expect(source, contains('class _TheatreMark'));
    expect(source, contains('const PandoraMark(size: 132'));
    expect(source, contains('MediaQuery.of(context).disableAnimations'));
    expect(source, contains('AnimationController('));
    expect(source, contains('PandoraOwnerBuildStage.previewReady'));
  });

  test('customer journey does not name infrastructure providers', () {
    final source =
        File('lib/features/simple/project_journey_flow.dart').readAsStringSync();
    for (final forbidden in const [
      'Vercel',
      'Supabase',
      'GitHub',
      'GitLab',
      'Gemini',
      'GPT',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
  });
}
