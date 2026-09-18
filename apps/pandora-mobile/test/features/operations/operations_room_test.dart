import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/features/operations/operations_room_screen.dart';

void main() {
  test('operations room exposes the six canonical roles', () {
    expect(
      operationsRoomRoles.map((role) => role.name).toList(),
      <String>[
        'ATHENA',
        'APOLLO',
        'HERMES',
        'HEPHAESTUS',
        'THEMIS',
        'ARTEMIS',
      ],
    );
  });

  test('reply parser splits role blocks in order', () {
    final messages = parseOperationsRoomReply(
      '[[ROLE:APOLLO]]\nUX view.\n'
      '[[ROLE:HEPHAESTUS]]\nEngineering view.\n'
      '[[ROLE:ATHENA]]\nDecision.',
    );

    expect(messages, hasLength(3));
    expect(messages[0].role, 'APOLLO');
    expect(messages[0].text, 'UX view.');
    expect(messages[1].role, 'HEPHAESTUS');
    expect(messages[2].role, 'ATHENA');
    expect(messages[2].text, 'Decision.');
  });

  test('reply parser attributes plain responses to Athena', () {
    final messages = parseOperationsRoomReply('I have the room.');
    expect(messages, hasLength(1));
    expect(messages.single.role, 'ATHENA');
    expect(messages.single.text, 'I have the room.');
  });

  test('mentions are explicit and case insensitive', () {
    expect(
      operationsRoomMentions('Ask @Apollo and @ARTEMIS to review this.'),
      <String>{'APOLLO', 'ARTEMIS'},
    );
    expect(operationsRoomMentions('Athena should review this.'), isEmpty);
  });

  test('role text preserves independently targeted specialist output', () {
    expect(
      operationsRoomRoleText(
        '[[ROLE:THEMIS]]\nSecurity view.',
        'THEMIS',
      ),
      'Security view.',
    );
    expect(
      operationsRoomRoleText('Unmarked independent view.', 'APOLLO'),
      'Unmarked independent view.',
    );
  });
}
