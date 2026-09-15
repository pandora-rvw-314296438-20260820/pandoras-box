import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_provisioning_bootstrap.dart';

Map<String, Object?> _bootstrap() => {
      'schemaVersion': '1.0.0',
      'platform': 'android',
      'runtimeLocation': 'on_device',
      'enrollmentMode': 'self_service_app_v1',
      'readiness': 'ready_for_on_device_enrollment',
      'normalOperationRequiresDesktop': false,
      'adbRequiredForNormalOperation': false,
      'developmentBridgePolicy': 'optional_recovery_only',
      'rootRequired': false,
      'bootloaderUnlockRequired': false,
      'deviceOwnerProvisioned': false,
      'deviceOwnerRequiredForNormalOperation': false,
      'homeRoleHeld': false,
      'protectedAppReauthenticationRequired': true,
      'protectedAppAccessPolicy': 'deny_private_app_data_and_credentials',
      'setupSteps': [
        {
          'id': 'app_installation',
          'authority': 'installer',
          'state': 'complete',
          'normalOperationDependency': true,
        },
        {
          'id': 'in_app_authentication',
          'authority': 'user',
          'state': 'session_scoped_user_action',
          'normalOperationDependency': true,
        },
        {
          'id': 'android_roles_and_permissions',
          'authority': 'user',
          'state': 'capability_scoped_on_demand',
          'normalOperationDependency': false,
        },
        {
          'id': 'oem_background_reliability',
          'authority': 'user',
          'state': 'optional_manual_oem_control',
          'normalOperationDependency': false,
        },
      ],
      'recoveryPaths': [
        {
          'id': 'android_settings',
          'authority': 'user',
          'normalOperationDependency': false,
        },
        {
          'id': 'app_details',
          'authority': 'user',
          'normalOperationDependency': false,
        },
        {
          'id': 'battery_optimization_settings',
          'authority': 'user',
          'normalOperationDependency': false,
        },
        {
          'id': 'adb_development_bridge',
          'authority': 'development_only',
          'normalOperationDependency': false,
        },
      ],
    };

void main() {
  test('parses no-PC self-service bootstrap', () {
    final bootstrap = PandoraProvisioningBootstrap.fromMap(_bootstrap());

    expect(bootstrap.readiness, 'ready_for_on_device_enrollment');
    expect(bootstrap.deviceOwnerProvisioned, isFalse);
    expect(bootstrap.homeRoleHeld, isFalse);
    expect(bootstrap.setupSteps.length, 4);
    expect(
      bootstrap.recoveryPaths.any(
        (path) => path['id'] == 'adb_development_bridge',
      ),
      isTrue,
    );
  });

  test('rejects normal-operation desktop or privileged dependencies', () {
    for (final key in [
      'normalOperationRequiresDesktop',
      'adbRequiredForNormalOperation',
      'rootRequired',
      'bootloaderUnlockRequired',
      'deviceOwnerRequiredForNormalOperation',
    ]) {
      final invalid = _bootstrap();
      invalid[key] = true;
      expect(
        () => PandoraProvisioningBootstrap.fromMap(invalid),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('rejects protected-app boundary weakening', () {
    final noReauth = _bootstrap();
    noReauth['protectedAppReauthenticationRequired'] = false;
    expect(
      () => PandoraProvisioningBootstrap.fromMap(noReauth),
      throwsFormatException,
    );

    final privateData = _bootstrap();
    privateData['protectedAppAccessPolicy'] = 'allow_private_app_data';
    expect(
      () => PandoraProvisioningBootstrap.fromMap(privateData),
      throwsFormatException,
    );
  });

  test('rejects credentials or secrets in bootstrap evidence', () {
    for (final secretKey in ['token', 'accessToken', 'PrivateKey']) {
      final invalid = _bootstrap();
      final steps = List<Map<String, Object?>>.from(
        invalid['setupSteps']! as List,
      );
      steps[0] = Map<String, Object?>.from(steps[0])..[secretKey] = 'forbidden';
      invalid['setupSteps'] = steps;

      expect(
        () => PandoraProvisioningBootstrap.fromMap(invalid),
        throwsFormatException,
        reason: secretKey,
      );
    }
  });

  test('keeps ADB recovery-only and outside normal operation', () {
    final invalid = _bootstrap();
    final recovery = List<Map<String, Object?>>.from(
      invalid['recoveryPaths']! as List,
    );
    final adbIndex = recovery.indexWhere(
      (path) => path['id'] == 'adb_development_bridge',
    );
    recovery[adbIndex] = Map<String, Object?>.from(recovery[adbIndex])
      ..['normalOperationDependency'] = true;
    invalid['recoveryPaths'] = recovery;
    expect(
      () => PandoraProvisioningBootstrap.fromMap(invalid),
      throwsFormatException,
    );

    final wrongAuthority = _bootstrap();
    final wrongRecovery = List<Map<String, Object?>>.from(
      wrongAuthority['recoveryPaths']! as List,
    );
    final wrongAdbIndex = wrongRecovery.indexWhere(
      (path) => path['id'] == 'adb_development_bridge',
    );
    wrongRecovery[wrongAdbIndex] = Map<String, Object?>.from(
      wrongRecovery[wrongAdbIndex],
    )..['authority'] = 'user';
    wrongAuthority['recoveryPaths'] = wrongRecovery;

    expect(
      () => PandoraProvisioningBootstrap.fromMap(wrongAuthority),
      throwsFormatException,
    );
  });
  test('requires every on-device enrollment step exactly once', () {
    final missing = _bootstrap();
    final missingSteps = List<Map<String, Object?>>.from(
      missing['setupSteps']! as List,
    )..removeWhere((step) => step['id'] == 'in_app_authentication');
    missing['setupSteps'] = missingSteps;
    expect(
      () => PandoraProvisioningBootstrap.fromMap(missing),
      throwsFormatException,
    );

    final duplicate = _bootstrap();
    final duplicateSteps =
        List<Map<String, Object?>>.from(duplicate['setupSteps']! as List)
          ..add(
            Map<String, Object?>.from(
              (duplicate['setupSteps']! as List).first as Map,
            ),
          );
    duplicate['setupSteps'] = duplicateSteps;
    expect(
      () => PandoraProvisioningBootstrap.fromMap(duplicate),
      throwsFormatException,
    );
  });
}
