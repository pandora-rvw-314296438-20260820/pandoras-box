import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_communication_command.dart';
import 'package:pandora_mobile/core/device/pandora_communications.dart';

void main() {
  test('explicit call to bounded phone target is locally routable', () {
    final command = PandoraDeviceCommunicationCommand.tryParse(
      'Call +63 917 555 0123',
    );

    expect(command, isNotNull);
    expect(command!.kind, PandoraCommunicationKind.call);
    expect(command.recipient, '+63 917 555 0123');
    expect(command.recipientIsBounded, isTrue);
  });

  test(
    'named call target requires identity resolution instead of fake success',
    () {
      final command = PandoraDeviceCommunicationCommand.tryParse('Call Nocom');

      expect(command, isNotNull);
      expect(command!.kind, PandoraCommunicationKind.call);
      expect(command.recipient, 'Nocom');
      expect(command.recipientIsBounded, isFalse);
    },
  );

  test('quoted SMS carries bounded recipient and body', () {
    final command = PandoraDeviceCommunicationCommand.tryParse(
      'Text +639175550123 "Pandora test"',
    );

    expect(command, isNotNull);
    expect(command!.kind, PandoraCommunicationKind.sms);
    expect(command.recipientIsBounded, isTrue);
    expect(command.message, 'Pandora test');
    expect(command.messageIsReady, isTrue);
  });

  test('named SMS target fails closed pending contact resolution', () {
    final command = PandoraDeviceCommunicationCommand.tryParse(
      'Text Nocom "Pandora test"',
    );

    expect(command, isNotNull);
    expect(command!.kind, PandoraCommunicationKind.sms);
    expect(command.recipient, 'Nocom');
    expect(command.recipientIsBounded, isFalse);
    expect(command.message, 'Pandora test');
  });
}
