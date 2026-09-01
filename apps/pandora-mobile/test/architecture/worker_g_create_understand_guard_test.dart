import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Create Project follows the V2 intent-first journey', () {
    final source = File('lib/features/simple/project_create_experience.dart')
        .readAsStringSync();
    final projects =
        File('lib/features/simple/projects_screen.dart').readAsStringSync();
    final legacy = File('lib/features/simple/project_journey_flow.dart')
        .readAsStringSync();

    expect(source, contains(r'What do you want\nto make happen?'));
    expect(
      source,
      contains(
        'Describe the result in your own words. Pandora will choose the technical shape.',
      ),
    );
    expect(source, contains('name: _inferName(intent)'));
    expect(source, contains('buildKind: ProjectBuildKind.helpMeDecide'));
    expect(source, contains('submitIntent('));
    expect(source, contains('Here’s what Pandora will build.'));
    expect(source, contains("title: 'Build plan'"));
    expect(source, contains("label: 'Build it'"));
    expect(source, contains('ProjectBuildConversationScreen('));
    expect(source, isNot(contains('What Pandora understands')));
    expect(source, isNot(contains('Name your project')));
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
