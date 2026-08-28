import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Create Project follows the owner-first three-step journey', () {
    final source = File('lib/features/simple/project_create_experience.dart')
        .readAsStringSync();
    final projects =
        File('lib/features/simple/projects_screen.dart').readAsStringSync();
    final legacy = File('lib/features/simple/project_journey_flow.dart')
        .readAsStringSync();

    expect(source, contains('Name your project'));
    expect(source, contains('What do you want to build?'));
    expect(source, contains('What do you want Pandora to build?'));
    expect(source, contains('Here’s what I understood'));
    expect(source, contains("label: 'Build it'"));
    expect(source, contains("label: 'Change something'"));
    expect(projects, contains('const CreateProjectExperienceScreen()'));
    expect(legacy, isNot(contains('class CreateProjectFlowScreen')));
  });

  test('understanding is bound to the exact submitted intent', () {
    final source =
        File('lib/core/data/project_experience_api.dart').readAsStringSync();

    expect(source, contains(".from('pandora_project_intents')"));
    expect(source, contains(".from('pandora_project_specs')"));
    expect(source, contains("'source_intent_id'"));
    expect(source, contains('expectedSourceIntentId'));
    expect(source, contains("status != 'active'"));
  });

  test('Simple Mode create journey does not name infrastructure providers', () {
    final source = File('lib/features/simple/project_create_experience.dart')
        .readAsStringSync();

    for (final provider in <String>[
      'Vercel',
      'Supabase',
      'Gemini',
      'GPT',
      'GitHub',
      'GitLab',
      'Docker',
      'PostgreSQL',
    ]) {
      expect(source, isNot(contains(provider)));
    }
  });
}
