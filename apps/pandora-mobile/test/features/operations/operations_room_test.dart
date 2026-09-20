import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/operations/operations_room_screen.dart';

void main() {
  test('operations room exposes fourteen specialists with six core roles', () {
    expect(operationsRoomRoles, hasLength(14));
    expect(
      operationsRoomRoles.where((role) => role.core).map((role) => role.name),
      <String>[
        'ATHENA',
        'APOLLO',
        'HERMES',
        'HEPHAESTUS',
        'ARTEMIS',
        'THEMIS',
      ],
    );
    expect(
      operationsRoomRoles.map((role) => role.name).toSet(),
      containsAll(<String>{
        'MNEMOSYNE',
        'HESTIA',
        'IRIS',
        'ASCLEPIUS',
        'NIKE',
        'HECATE',
        'PROMETHEUS',
        'DEMETER',
      }),
    );
  });

  test('reply parser accepts every registered specialist marker', () {
    final reply = operationsRoomRoles
        .map((role) => '[[ROLE:${role.name}]]\n${role.name} view.')
        .join('\n');
    final messages = parseOperationsRoomReply(reply);
    expect(messages, hasLength(14));
    expect(messages.map((item) => item.role).toList(),
        operationsRoomRoles.map((role) => role.name).toList());
  });

  test('reply parser attributes plain responses to Athena', () {
    final messages = parseOperationsRoomReply('I have the room.');
    expect(messages, hasLength(1));
    expect(messages.single.role, 'ATHENA');
  });

  test('mentions are explicit and case insensitive across expanded roster', () {
    expect(
      operationsRoomMentions(
        'Ask @Apollo, @ARTEMIS, @Hecate and @Mnemosyne to review this.',
      ),
      <String>{'APOLLO', 'ARTEMIS', 'HECATE', 'MNEMOSYNE'},
    );
    expect(operationsRoomMentions('Athena should review this.'), isEmpty);
  });

  test('execution routing summons the mobile build specialists only', () {
    expect(
      operationsRoomRecommendedRoles(
        'Fix the mobile chat and get me a tested APK.',
        OperationsRoomMode.execution,
      ),
      <String>['APOLLO', 'HEPHAESTUS', 'HERMES', 'ARTEMIS'],
    );
  });

  test('performance routing summons reliability and recovery specialists', () {
    expect(
      operationsRoomRecommendedRoles(
        'Pandora is slow on my phone.',
        OperationsRoomMode.execution,
      ),
      <String>['HEPHAESTUS', 'HESTIA', 'ASCLEPIUS', 'ARTEMIS'],
    );
  });

  test('model routing summons Hecate Nike and Prometheus', () {
    expect(
      operationsRoomRecommendedRoles(
        'Which models should Pandora use for coding, research and cheap everyday requests?',
        OperationsRoomMode.execution,
      ),
      <String>['HECATE', 'NIKE', 'PROMETHEUS'],
    );
  });

  test('phone-local AI routing prioritizes implementation and verification', () {
    expect(
      operationsRoomRecommendedRoles(
        'Run Qwen3 4B Q4_K_M on the phone and verify GPU/NPU acceleration.',
        OperationsRoomMode.execution,
      ),
      <String>['HECATE', 'HEPHAESTUS', 'ARTEMIS', 'THEMIS'],
    );
  });

  test('operations room exposes the active phone-local architecture constraint', () {
    expect(operationsRoomActiveArchitecture, contains('qwen2.5-3b-instruct-q4_k_m.gguf'));
    expect(operationsRoomActiveArchitecture, contains('approved cloud capability'));
        expect(operationsRoomActiveArchitecture, contains('RDP-hosted LLMs'));
    expect(operationsRoomActiveArchitecture, contains('AWS'));
    expect(operationsRoomActiveArchitecture, contains('Bedrock'));
  });

  test('direct mention overrides automatic routing', () {
    expect(
      operationsRoomRecommendedRoles(
        '@Themis review the permission model.',
        OperationsRoomMode.execution,
      ),
      <String>['THEMIS'],
    );
    expect(
      operationsRoomRecommendedRoles(
        '@Athena handle this yourself.',
        OperationsRoomMode.execution,
      ),
      isEmpty,
    );
  });

  test('incident mode narrows the room to incident specialists', () {
    expect(
      operationsRoomRecommendedRoles(
        'Production is failing.',
        OperationsRoomMode.incident,
      ),
      <String>[
        'HEPHAESTUS',
        'THEMIS',
        'ARTEMIS',
        'ASCLEPIUS',
        'HESTIA',
      ],
    );
  });

  test('role text preserves independently targeted specialist output', () {
    expect(
      operationsRoomRoleText(
        '[[ROLE:DEMETER]]\nData view.',
        'DEMETER',
      ),
      'Data view.',
    );
    expect(
      operationsRoomRoleText('Unmarked independent view.', 'APOLLO'),
      'Unmarked independent view.',
    );
  });
}
