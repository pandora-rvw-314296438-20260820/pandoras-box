import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_device_agent.dart';

Map<String, Object?> _manifest({
  bool desktopRequired = false,
  bool rootRequired = false,
  bool bootloaderUnlockRequired = false,
  bool deviceOwnerProvisioned = false,
  List<Object?>? capabilities,
}) {
  return {
    'schemaVersion': '1.0.0',
    'platform': 'android',
    'adapterId': 'android_public_v1',
    'sdkInt': 36,
    'deviceOwnerProvisioned': deviceOwnerProvisioned,
    'normalOperationRequiresDesktop': desktopRequired,
    'rootRequired': rootRequired,
    'bootloaderUnlockRequired': bootloaderUnlockRequired,
    'protectedAppAccessPolicy': 'deny_private_app_data_and_credentials',
    'developmentBridgePolicy': 'optional_not_trust_dependency',
    'capabilities': capabilities ??
        [
          {
            'id': 'device.identity',
            'authority': 'public_app',
            'availability': 'available',
            'reason': 'Public Android build identity.',
            'normalOperationDependency': true,
          },
          {
            'id': 'shell.arbitrary',
            'authority': 'policy_denied',
            'availability': 'forbidden',
            'reason': 'Arbitrary shell is outside the Device Agent contract.',
            'normalOperationDependency': false,
          },
        ],
  };
}

void main() {
  test('parses OEM-neutral phone-only manifest', () {
    final manifest = PandoraDeviceCapabilityManifest.fromMap(_manifest());

    expect(manifest.adapterId, 'android_public_v1');
    expect(manifest.normalOperationRequiresDesktop, isFalse);
    expect(manifest.rootRequired, isFalse);
    expect(manifest.bootloaderUnlockRequired, isFalse);
    expect(
      manifest.capability('shell.arbitrary')?.availability,
      PandoraDeviceAvailability.forbidden,
    );
  });

  test('rejects desktop dependency', () {
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(desktopRequired: true),
      ),
      throwsFormatException,
    );
  });

  test('rejects root and bootloader requirements', () {
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(rootRequired: true),
      ),
      throwsFormatException,
    );
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(bootloaderUnlockRequired: true),
      ),
      throwsFormatException,
    );
  });

  test('rejects duplicate capability identifiers', () {
    final duplicate = {
      'id': 'device.identity',
      'authority': 'public_app',
      'availability': 'available',
      'reason': 'Duplicate.',
      'normalOperationDependency': true,
    };
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(capabilities: [duplicate, duplicate]),
      ),
      throwsFormatException,
    );
  });

  test('forbidden capability must be policy denied', () {
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(
          capabilities: [
            {
              'id': 'unsafe',
              'authority': 'public_app',
              'availability': 'forbidden',
              'reason': 'Unsafe.',
              'normalOperationDependency': false,
            },
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('unprovisioned Device Owner cannot advertise available authority', () {
    expect(
      () => PandoraDeviceCapabilityManifest.fromMap(
        _manifest(
          capabilities: [
            {
              'id': 'device.owner.control',
              'authority': 'device_owner',
              'availability': 'available',
              'reason': 'Requires Device Owner.',
              'normalOperationDependency': false,
            },
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('safe diagnostic request encodes an allowlisted kind only', () {
    const request = PandoraSafeDiagnosticRequest(
      PandoraSafeDiagnosticKind.permissionState,
    );

    expect(request.toMap(), {'kind': 'permission_state'});
    expect(request.toMap().containsKey('command'), isFalse);
  });
}
