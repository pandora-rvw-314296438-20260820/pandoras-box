import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/app/pandora_core_client_scope.dart';
import 'package:pandora_mobile/core/data/pandora_core_api.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';

const _organizationId = '11111111-1111-4111-8111-111111111111';
const _otherOrganizationId = '22222222-2222-4222-8222-222222222222';
final _now = DateTime.utc(2026, 10, 3, 12);

PandoraCoreRecord _receipt() => <String, dynamic>{
      'entry_id': 'entry-verified',
      'organization_id': _organizationId,
      'property_id': 'property-client',
      'workspace_type': 'enterprise',
      'display_name': 'Client workspace name',
      'expires_at': _now.add(const Duration(minutes: 5)).toIso8601String(),
    };

Matcher get _throwsScopeMismatch => throwsA(
      isA<PandoraCoreFailure>().having(
        (failure) => failure.code,
        'code',
        'SCOPE_MISMATCH',
      ),
    );

PandoraClientEntry _verify(PandoraCoreRecord receipt) =>
    PandoraClientEntry.verify(
      receipt,
      requestedOrganizationId: _organizationId,
      now: _now,
    );

void main() {
  group('Core money precision', () {
    test('parses decimal amounts exactly through six places', () {
      expect(parseCoreMoneyMicros('0.000001'), 1);
      expect(parseCoreMoneyMicros('29900.123456'), 29900123456);
      expect(parseCoreMoneyMicros(' 0.10 '), 100000);
      expect(parseCoreMoneyMicros('100000000'), 100000000000000);
    });

    test('rejects rounding, nondecimal input and out-of-range amounts', () {
      for (final value in <String>[
        '',
        '-1',
        '+1',
        'NaN',
        'Infinity',
        '1e3',
        '1,000',
        '0.0000001',
        '100000000.000001',
        '9999999999999999999999999',
      ]) {
        expect(parseCoreMoneyMicros(value), isNull, reason: value);
      }
    });

    test('formatting preserves micros and distinguishes missing values', () {
      expect(formatCoreMoneyMicros(1), '0.000001');
      expect(formatCoreMoneyMicros(29900123456), '29900.123456');
      expect(formatCoreMoneyMicros(100000), '0.10');
      expect(formatCoreMoneyMicros(0), '0.00');
      expect(formatCoreMoneyMicros(-1), '-0.000001');
      expect(formatCoreMoneyMicros(null), '—');
      for (final amount in <int>[0, 1, 100000, 29900123456, 100000000000000]) {
        expect(parseCoreMoneyMicros(formatCoreMoneyMicros(amount)), amount);
      }
    });
  });

  group('PandoraClientEntry.verify', () {
    test('accepts a live receipt scoped to the requested organization', () {
      final entry = _verify(_receipt());

      expect(entry.entryId, 'entry-verified');
      expect(entry.organizationId, _organizationId);
      expect(entry.propertyId, 'property-client');
      expect(entry.workspaceType, 'enterprise');
      expect(entry.displayName, 'Client workspace name');
      expect(entry.expiresAt, _now.add(const Duration(minutes: 5)));
    });

    test('supports a receipt without optional property or display name', () {
      final receipt = _receipt()
        ..remove('property_id')
        ..remove('display_name');

      final entry = _verify(receipt);

      expect(entry.propertyId, isNull);
      expect(entry.displayName, 'Client workspace');
      expect(entry.organizationId, _organizationId);
    });

    test('rejects a receipt for another organization', () {
      final receipt = _receipt()..['organization_id'] = _otherOrganizationId;

      expect(() => _verify(receipt), _throwsScopeMismatch);
    });

    for (final field in <String>[
      'entry_id',
      'organization_id',
      'workspace_type',
    ]) {
      test('rejects a missing $field', () {
        final receipt = _receipt()..remove(field);

        expect(() => _verify(receipt), _throwsScopeMismatch);
      });

      test('rejects null, empty, or whitespace $field', () {
        for (final value in <Object?>[null, '', ' \t\n ']) {
          final receipt = _receipt()..[field] = value;

          expect(
            () => _verify(receipt),
            _throwsScopeMismatch,
            reason: '$field must be present and nonempty: $value',
          );
        }
      });
    }

    test('rejects a missing expiry', () {
      final receipt = _receipt()..remove('expires_at');

      expect(() => _verify(receipt), _throwsScopeMismatch);
    });

    test('rejects an unparseable expiry', () {
      for (final expiry in <Object?>[null, '', 'not-a-date', '2026-10']) {
        final receipt = _receipt()..['expires_at'] = expiry;

        expect(
          () => _verify(receipt),
          _throwsScopeMismatch,
          reason: 'Expiry must parse as a date: $expiry',
        );
      }
    });

    test('rejects an expiry before the verification time', () {
      final receipt = _receipt()
        ..['expires_at'] =
            _now.subtract(const Duration(microseconds: 1)).toIso8601String();

      expect(() => _verify(receipt), _throwsScopeMismatch);
    });

    test('rejects an expiry exactly at the verification time', () {
      final receipt = _receipt()..['expires_at'] = _now.toIso8601String();

      expect(() => _verify(receipt), _throwsScopeMismatch);
    });

    test('accepts an expiry strictly after the verification time', () {
      final expiry = _now.add(const Duration(microseconds: 1));
      final receipt = _receipt()..['expires_at'] = expiry.toIso8601String();

      expect(_verify(receipt).expiresAt, expiry);
    });

    test('compares an explicit timezone offset by its instant', () {
      final receipt = _receipt()..['expires_at'] = '2026-10-03T14:00:00+02:00';

      expect(() => _verify(receipt), _throwsScopeMismatch);
    });

    test('an empty requested organization cannot verify missing scope', () {
      final receipt = _receipt()..remove('organization_id');

      expect(
        () => PandoraClientEntry.verify(
          receipt,
          requestedOrganizationId: '',
          now: _now,
        ),
        _throwsScopeMismatch,
      );
    });

    test('an empty requested organization cannot verify blank scope', () {
      for (final organization in <Object?>[null, '', ' \t ']) {
        final receipt = _receipt()..['organization_id'] = organization;

        expect(
          () => PandoraClientEntry.verify(
            receipt,
            requestedOrganizationId: '',
            now: _now,
          ),
          _throwsScopeMismatch,
          reason: 'Blank organizations do not establish client scope',
        );
      }
    });
  });

  group('PandoraIntelligenceTurn core navigation handoff', () {
    test('preserves the target section, action, and organization', () {
      final turn = PandoraIntelligenceTurn.fromJson(<String, dynamic>{
        'threadId': 'thread-core',
        'reply': 'Opening the client.',
        'handoff': <String, dynamic>{
          'required': true,
          'request': 'Open the client workspace',
          'source': 'pandora_core',
          'kind': 'core_navigation',
          'section': 'clients',
          'action': 'manage_users',
          'organizationId': _organizationId,
        },
      });

      final handoff = turn.handoff!;
      expect(handoff.request, 'Open the client workspace');
      expect(handoff.source, 'pandora_core');
      expect(handoff.kind, 'core_navigation');
      expect(handoff.section, 'clients');
      expect(handoff.action, 'manage_users');
      expect(handoff.organizationId, _organizationId);
      expect(handoff.projectId, isNull);
    });

    test('does not create a handoff without an explicit required flag', () {
      for (final requiredFlag in <Object?>[null, false, 'true', 1]) {
        final turn = PandoraIntelligenceTurn.fromJson(<String, dynamic>{
          'threadId': 'thread-core',
          'reply': 'Here is the client information.',
          'handoff': <String, dynamic>{
            'required': requiredFlag,
            'request': 'Open the client workspace',
            'kind': 'core_navigation',
            'section': 'clients',
            'organizationId': _organizationId,
          },
        });

        expect(turn.handoff, isNull, reason: 'required: $requiredFlag');
      }
    });

    test('retains existing project handoffs without core navigation fields',
        () {
      final turn = PandoraIntelligenceTurn.fromJson(<String, dynamic>{
        'threadId': 'thread-project',
        'reply': 'Continuing the project.',
        'handoff': <String, dynamic>{
          'required': true,
          'request': 'Continue building the project',
          'projectId': 'project-existing',
          'source': 'project',
        },
      });

      final handoff = turn.handoff!;
      expect(handoff.projectId, 'project-existing');
      expect(handoff.request, 'Continue building the project');
      expect(handoff.source, 'project');
      expect(handoff.kind, isNull);
      expect(handoff.section, isNull);
      expect(handoff.action, isNull);
      expect(handoff.organizationId, isNull);
    });
  });
}
