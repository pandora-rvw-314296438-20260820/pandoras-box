import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_communications.dart';

void main() {
  test('call handoff keeps system dialer confirmation boundary', () {
    final request = PandoraCommunicationRequest.call('+63 917 555 0123');

    expect(
      request.toMap(),
      <String, Object?>{
        'kind': 'call',
        'recipient': '+63 917 555 0123',
      },
    );
  });

  test('SMS handoff carries bounded body to system composer', () {
    final request = PandoraCommunicationRequest.sms(
      '09175550123',
      message: 'Running a little late.',
    );

    expect(
      request.toMap(),
      <String, Object?>{
        'kind': 'sms',
        'recipient': '09175550123',
        'message': 'Running a little late.',
      },
    );
  });

  test('communication target rejects URI/control injection', () {
    for (final recipient in <String>[
      '',
      'tel:+639175550123',
      '0917\n5550123',
      '0917?body=unsafe',
      '0917%0A5550123',
    ]) {
      expect(
        () => PandoraCommunicationRequest.call(recipient).toMap(),
        throwsFormatException,
      );
    }
  });

  test('SMS body is bounded before native handoff', () {
    expect(
      () => PandoraCommunicationRequest.sms(
        '09175550123',
        message: 'x'.padRight(2001, 'x'),
      ).toMap(),
      throwsFormatException,
    );
  });

  test('handoff result requires explicit user confirmation', () {
    final result = PandoraCommunicationHandoffResult.fromMap(
      <String, Object?>{
        'kind': 'call',
        'status': 'opened',
        'handoff': 'system_dialer',
        'userConfirmationRequired': true,
      },
    );

    expect(result.opened, isTrue);
    expect(result.userConfirmationRequired, isTrue);
  });

  test('handoff result rejects silent execution semantics', () {
    expect(
      () => PandoraCommunicationHandoffResult.fromMap(
        <String, Object?>{
          'kind': 'sms',
          'status': 'opened',
          'handoff': 'system_sms_composer',
          'userConfirmationRequired': false,
        },
      ),
      throwsFormatException,
    );
  });

  test('direct SMS parses platform-submitted truth without claiming sent', () {
    final result = PandoraDirectCommunicationResult.fromMap(
      <String, Object?>{
        'operationId': 'direct-sms-12345',
        'kind': 'sms',
        'state': 'submitted',
        'terminal': false,
        'acceptedByPlatform': true,
        'duplicatePrevented': false,
        'requiredPermission': 'android.permission.SEND_SMS',
        'failure': null,
        'updatedAtEpochMs': 123,
      },
    );
    expect(result.state, PandoraDirectCommunicationState.submitted);
    expect(result.acceptedByPlatform, isTrue);
    expect(result.terminal, isFalse);
  });

  test('direct callback failure may preserve earlier platform acceptance', () {
    final result = PandoraDirectCommunicationResult.fromMap(
      <String, Object?>{
        'operationId': 'direct-sms-67890',
        'kind': 'sms',
        'state': 'failed',
        'terminal': true,
        'acceptedByPlatform': true,
        'duplicatePrevented': false,
        'failure': 'android_result_1',
        'updatedAtEpochMs': 456,
      },
    );
    expect(result.state, PandoraDirectCommunicationState.failed);
    expect(result.acceptedByPlatform, isTrue);
  });
}
