import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_device_compatibility_profile.dart';

Map<String, Object?> _profile() => {
      'schemaVersion': '1.0.0',
      'platform': 'android',
      'sdkInt': 36,
      'cpu': {
        'supportedAbis': ['arm64-v8a'],
        'logicalProcessors': 8,
        'source': 'android_public_runtime',
      },
      'memory': {'totalBytes': 8000000000, 'source': 'activity_manager_public'},
      'storage': {
        'scope': 'app_data_filesystem',
        'totalBytes': 128000000000,
        'availableBytes': 64000000000,
        'source': 'statfs_public',
      },
      'accelerators': {
        'npu': {
          'availability': 'unknown',
          'evidence': 'not_probed_by_stable_public_api',
        },
      },
      'roles': {
        'deviceOwnerProvisioned': false,
        'homeRoleHeld': true,
        'dialerRoleAvailability': 'available',
        'smsRoleAvailability': 'permission_required',
      },
      'sensors': {
        'cameraHardware': true,
        'microphoneHardware': true,
        'telephonyHardware': true,
        'bluetoothHardware': true,
        'hardwarePresenceOnly': true,
      },
      'oem': {
        'adapterId': 'xiaomi_public_v1',
        'manufacturer': 'Xiaomi',
        'brand': 'Redmi',
        'xiaomiFamily': true,
        'autostartManagement': 'manual_oem_control',
      },
      'constraints': {
        'normalOperationRequiresDesktop': false,
        'rootRequired': false,
        'bootloaderUnlockRequired': false,
        'hiddenOemApiRequired': false,
        'protectedAppAccessPolicy': 'deny_private_app_data_and_credentials',
        'developmentBridgePolicy': 'optional_not_trust_dependency',
      },
    };
void main() {
  test('parses portable public compatibility profile', () {
    final profile = PandoraDeviceCompatibilityProfile.fromMap(_profile());

    expect(profile.sdkInt, 36);
    expect(profile.cpu['logicalProcessors'], 8);
    expect(profile.memory['totalBytes'], 8000000000);
    expect(profile.storage['scope'], 'app_data_filesystem');
    expect(profile.roles['deviceOwnerProvisioned'], isFalse);
    expect(profile.sensors['hardwarePresenceOnly'], isTrue);
    expect(profile.oem['adapterId'], 'xiaomi_public_v1');
  });

  test('keeps NPU state unknown until a stable verifier exists', () {
    final invalid = _profile();
    final accelerators = Map<String, Object?>.from(
      invalid['accelerators']! as Map,
    );
    accelerators['npu'] = {
      'availability': 'available',
      'evidence': 'model_name_inference',
    };
    invalid['accelerators'] = accelerators;
    expect(
      () => PandoraDeviceCompatibilityProfile.fromMap(invalid),
      throwsFormatException,
    );
  });
  test('rejects desktop root bootloader and hidden OEM dependencies', () {
    for (final key in [
      'normalOperationRequiresDesktop',
      'rootRequired',
      'bootloaderUnlockRequired',
      'hiddenOemApiRequired',
    ]) {
      final invalid = _profile();
      final constraints = Map<String, Object?>.from(
        invalid['constraints']! as Map,
      );
      constraints[key] = true;
      invalid['constraints'] = constraints;
      expect(
        () => PandoraDeviceCompatibilityProfile.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('rejects identifying data anywhere in the profile', () {
    final invalid = _profile();
    final oem = Map<String, Object?>.from(invalid['oem']! as Map);
    oem['serial'] = 'device-secret';
    invalid['oem'] = oem;
    expect(
      () => PandoraDeviceCompatibilityProfile.fromMap(invalid),
      throwsFormatException,
    );
  });
  test('sensor hardware facts cannot imply permission grants', () {
    final invalid = _profile();
    final sensors = Map<String, Object?>.from(invalid['sensors']! as Map);
    sensors['hardwarePresenceOnly'] = false;
    invalid['sensors'] = sensors;
    expect(
      () => PandoraDeviceCompatibilityProfile.fromMap(invalid),
      throwsFormatException,
    );
  });

  test('rejects invalid portable hardware metrics', () {
    final invalidCpu = _profile();
    final cpu = Map<String, Object?>.from(invalidCpu['cpu']! as Map);
    cpu['logicalProcessors'] = 0;
    invalidCpu['cpu'] = cpu;
    expect(
      () => PandoraDeviceCompatibilityProfile.fromMap(invalidCpu),
      throwsFormatException,
    );

    final invalidStorage = _profile();
    final storage = Map<String, Object?>.from(
      invalidStorage['storage']! as Map,
    );
    storage['availableBytes'] = -1;
    invalidStorage['storage'] = storage;
    expect(
      () => PandoraDeviceCompatibilityProfile.fromMap(invalidStorage),
      throwsFormatException,
    );
  });
}
