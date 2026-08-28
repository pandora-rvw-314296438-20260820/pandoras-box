import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_user_admin_api.dart';

void main() {
  group('Pandora team models', () {
    test('normalizes member payloads and presentation labels', () {
      final member = PandoraTeamMember.fromJson(<String, dynamic>{
        'id': '11111111-1111-4111-8111-111111111111',
        'email': 'person@example.com',
        'displayName': 'Ada Lovelace',
        'role': 'operator',
        'status': 'active',
        'joinedAt': '2026-08-26T00:00:00Z',
      });

      expect(member.primaryLabel, 'Ada Lovelace');
      expect(member.initials, 'AL');
      expect(member.isActive, isTrue);
      expect(member.isInvited, isFalse);
      expect(member.joinedAt, isNotNull);
    });

    test('invite payload trims values without adding authority', () {
      const request = PandoraInviteRequest(
        email: ' PERSON@EXAMPLE.COM ',
        displayName: ' Person Name ',
        timezone: ' Asia/Manila ',
        role: 'member',
      );

      expect(request.toJson(), <String, dynamic>{
        'email': 'person@example.com',
        'displayName': 'Person Name',
        'timezone': 'Asia/Manila',
        'role': 'member',
      });
    });

    test('maps safe backend failure fields', () {
      final failure = PandoraUserAdminFailure.fromPayload(
        <String, dynamic>{
          'code': 'ROLE_GRANT_NOT_ALLOWED',
          'plainMessage': 'Only an owner can grant this role.',
          'requestId': 'request-123',
        },
        fallbackCode: 'FAILED',
        fallbackMessage: 'Failed.',
      );

      expect(failure.code, 'ROLE_GRANT_NOT_ALLOWED');
      expect(failure.message, 'Only an owner can grant this role.');
      expect(failure.requestId, 'request-123');
    });
  });
}
