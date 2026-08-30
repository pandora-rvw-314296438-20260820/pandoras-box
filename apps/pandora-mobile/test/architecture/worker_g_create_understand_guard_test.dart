import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Create Project becomes a Pandora conversation before build', () {
    final create = File('lib/features/simple/project_create_experience.dart')
        .readAsStringSync();
    final conversation = File(
      'lib/features/simple/project_conversation_screen.dart',
    ).readAsStringSync();
    final projects = File('lib/features/simple/projects_screen.dart')
        .readAsStringSync();
    final legacy = File('lib/features/simple/project_journey_flow.dart')
        .readAsStringSync();

    expect(create, contains('Name your project'));
    expect(create, contains('What do you want to build?'));
    expect(create, contains('What do you want Pandora to build?'));
    expect(create, contains('ProjectConversationScreen('));
    expect(conversation, contains('Build it with Pandora'));
    expect(
      conversation,
      contains('I understand. Here’s the prototype I’m going to build.'),
    );
    expect(conversation, contains("? 'Build updated preview'"));
    expect(conversation, contains(": 'Build this'"));
    expect(conversation, contains('Tell Pandora what to change…'));
    expect(
      conversation,
      contains('Nothing is built or published until you confirm it.'),
    );
    expect(projects, contains('const CreateProjectExperienceScreen()'));
    expect(legacy, isNot(contains('class CreateProjectFlowScreen')));
  });

  test(
    'project conversation is durable intent plus exact-source ProjectSpec',
    () {
      final api = File('lib/core/data/project_experience_api.dart')
          .readAsStringSync();
      final conversation = File(
        'lib/features/simple/project_conversation_screen.dart',
      ).readAsStringSync();

      expect(api, contains(".from('pandora_project_intents')"));
      expect(api, contains(".from('pandora_project_specs')"));
      expect(api, contains('conversationHistory'));
      expect(api, contains("'source_intent_id'"));
      expect(api, contains('expectedSourceIntentId'));
      expect(api, contains("status != 'active'"));
      expect(conversation, contains('conversationHistory('));
      expect(conversation, contains('submitIntent('));
    },
  );

  test('project changes reuse the same conversation surface', () {
    final iteration = File(
      'lib/features/simple/project_iteration_experience.dart',
    ).readAsStringSync();

    expect(iteration, contains('ProjectConversationScreen('));
    expect(iteration, contains('ProjectConversationMode.iteration'));
    expect(iteration, contains('Navigator.of(conversationContext).pop(true)'));
  });

  test(
    'Simple Mode project conversation does not name infrastructure providers',
    () {
      final source = [
        File('lib/features/simple/project_create_experience.dart')
            .readAsStringSync(),
        File('lib/features/simple/project_conversation_screen.dart')
            .readAsStringSync(),
      ].join('\n');

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
    },
  );
}
