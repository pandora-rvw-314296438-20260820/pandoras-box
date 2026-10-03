import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';

const _organizationId = '11111111-1111-4111-8111-111111111111';

Map<String, dynamic> _handoff() => {
      'required': true,
      'kind': 'core_navigation',
      'action': 'inspect',
      'section': 'clients',
      'request': 'Open Clients',
      'organizationId': _organizationId,
    };

PandoraIntelligenceMessage _restore(Map<String, dynamic> handoff,
        {String role = 'assistant'}) =>
    PandoraIntelligenceMessage.fromJson({
      'id': 'stored-assistant-message',
      'thread_id': 'stored-owner-thread',
      'author_role': role,
      'content': 'This client has an unresolved connection.',
      'created_at': '2026-10-03T12:00:00Z',
      'structured_response': {'handoff': handoff},
    });

void main() {
  test('stored assistant inspection retains its exact destination and scope',
      () {
    final message = _restore(_handoff());
    expect(message.content, 'This client has an unresolved connection.');
    expect(message.threadId, 'stored-owner-thread');
    final restored = message.inspectHandoff!;
    expect(restored.section, 'clients');
    expect(restored.organizationId, _organizationId);
    expect(restored.request, 'Open Clients');
    expect(restored.action, 'inspect');
    expect(restored.inspectionJson, _handoff());
    expect(
        PandoraIntelligenceHandoff.inspectFromJson(restored.inspectionJson)
            ?.organizationId,
        _organizationId);
    expect(
        _restore({..._handoff(), 'organizationId': null})
            .inspectHandoff
            ?.section,
        'clients');
  });

  test('stored commands never become replayable inspection actions', () {
    for (final action in ['create_client', 'manage_users', 'return_owner']) {
      expect(_restore({..._handoff(), 'action': action}).inspectHandoff, isNull,
          reason: 'Restoring $action must not reproduce an executable action.');
    }
    expect(_restore(_handoff(), role: 'user').inspectHandoff, isNull);
  });

  test('restored inspection metadata rejects missing bounds or invalid scope',
      () {
    for (final invalid in <Map<String, dynamic>>[
      {..._handoff(), 'required': false},
      {..._handoff(), 'kind': 'project_workspace_change'},
      {..._handoff(), 'section': 'unrecognized-route'},
      {..._handoff(), 'organizationId': 'foreign-scope-without-uuid'},
      {..._handoff(), 'organizationId': 123},
      {..._handoff(), 'organizationId': ''},
      {..._handoff(), 'request': ''},
      {..._handoff(), 'request': 'x' * 161},
    ]) {
      expect(_restore(invalid).inspectHandoff, isNull);
    }
  });
}
