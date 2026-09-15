import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_contacts.dart';

void main() {
  test('resolved Android contact exposes exactly one bounded number', () {
    final result = PandoraContactResolutionResult.fromMap(
      <String, Object?>{
        'status': 'resolved',
        'source': 'android_contacts',
        'resolution': 'exact',
        'displayName': 'Nocom',
        'phoneNumber': '+639175550123',
        'normalizedPhoneNumber': '+639175550123',
        'contactId': '42',
        'requiredPermission': 'android.permission.READ_CONTACTS',
        'candidates': <Object?>[],
      },
    );

    expect(result.isResolved, isTrue);
    expect(result.displayName, 'Nocom');
    expect(result.phoneNumber, '+639175550123');
    expect(result.candidates, isEmpty);
  });
  test('ambiguous contact resolution exposes only bounded candidates', () {
    final result = PandoraContactResolutionResult.fromMap(
      <String, Object?>{
        'status': 'ambiguous',
        'source': 'android_contacts',
        'resolution': 'unique_first_name',
        'reason': 'multiple_contacts',
        'requiredPermission': 'android.permission.READ_CONTACTS',
        'candidates': <Object?>[
          <String, Object?>{
            'contactId': '10',
            'displayName': 'Maria Cruz',
            'phoneNumber': '09175550123',
            'normalizedPhoneNumber': '09175550123',
          },
          <String, Object?>{
            'contactId': '11',
            'displayName': 'Maria Santos',
            'phoneNumber': '+639175550456',
            'normalizedPhoneNumber': '+639175550456',
          },
        ],
      },
    );

    expect(result.status, PandoraContactResolutionStatus.ambiguous);
    expect(result.candidates, hasLength(2));
    expect(result.phoneNumber, isNull);
  });
  test('permission-required result exposes no recipient identity', () {
    final result = PandoraContactResolutionResult.fromMap(
      <String, Object?>{
        'status': 'permission_required',
        'source': 'android_contacts',
        'resolution': null,
        'requiredPermission': 'android.permission.READ_CONTACTS',
        'candidates': <Object?>[],
      },
    );

    expect(result.status, PandoraContactResolutionStatus.permissionRequired);
    expect(result.phoneNumber, isNull);
    expect(result.candidates, isEmpty);
  });

  test('provider query failure is explicit unavailable truth', () {
    final result = PandoraContactResolutionResult.fromMap(
      <String, Object?>{
        'status': 'unavailable',
        'source': 'android_contacts',
        'resolution': null,
        'reason': 'contacts_query_failed',
        'requiredPermission': 'android.permission.READ_CONTACTS',
        'candidates': <Object?>[],
      },
    );

    expect(result.status, PandoraContactResolutionStatus.unavailable);
    expect(result.reason, 'contacts_query_failed');
    expect(result.phoneNumber, isNull);
    expect(result.candidates, isEmpty);
  });

  test('resolved contact rejects malformed recipient evidence', () {
    expect(
      () => PandoraContactResolutionResult.fromMap(
        <String, Object?>{
          'status': 'resolved',
          'source': 'android_contacts',
          'resolution': 'exact',
          'displayName': 'Unsafe',
          'phoneNumber': 'tel:+63917',
          'normalizedPhoneNumber': '+63917',
          'contactId': '9',
          'requiredPermission': 'android.permission.READ_CONTACTS',
          'candidates': <Object?>[],
        },
      ),
      throwsFormatException,
    );
  });
}
