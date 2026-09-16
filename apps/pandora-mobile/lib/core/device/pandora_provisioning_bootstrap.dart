import 'package:flutter/services.dart';

Map<String, Object?> _bootstrapMap(Object? raw, String label) {
  if (raw is! Map) {
    throw FormatException('$label must be a map.');
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _bootstrapString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _bootstrapBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

List<Map<String, Object?>> _bootstrapList(Object? raw, String label) {
  if (raw is! List) {
    throw FormatException('$label must be a list.');
  }
  return List<Map<String, Object?>>.unmodifiable(
    raw.map<Map<String, Object?>>(
      (item) => Map<String, Object?>.unmodifiable(
        _bootstrapMap(item, label),
      ),
    ),
  );
}

void _rejectBootstrapSecrets(Map<String, Object?> map) {
  const forbiddenFragments = {
    'password',
    'token',
    'otp',
    'secret',
    'privatekey',
    'servicerolekey',
  };
  void walk(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String) {
          final normalizedKey = (entry.key as String).toLowerCase();
          if (forbiddenFragments.any(normalizedKey.contains)) {
            throw const FormatException(
              'Provisioning bootstrap must not carry credentials or secrets.',
            );
          }
        }
        walk(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  walk(map);
}

class PandoraProvisioningBootstrap {
  const PandoraProvisioningBootstrap({
    required this.readiness,
    required this.deviceOwnerProvisioned,
    required this.homeRoleHeld,
    required this.setupSteps,
    required this.recoveryPaths,
  });

  final String readiness;
  final bool deviceOwnerProvisioned;
  final bool homeRoleHeld;
  final List<Map<String, Object?>> setupSteps;
  final List<Map<String, Object?>> recoveryPaths;

  factory PandoraProvisioningBootstrap.fromMap(Object? raw) {
    final map = _bootstrapMap(raw, 'provisioning bootstrap');
    if (_bootstrapString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported provisioning bootstrap schema.');
    }
    if (_bootstrapString(map, 'platform') != 'android') {
      throw const FormatException('Provisioning bootstrap must be Android.');
    }
    if (_bootstrapString(map, 'runtimeLocation') != 'on_device' ||
        _bootstrapString(map, 'enrollmentMode') != 'self_service_app_v1') {
      throw const FormatException(
        'Normal Pandora bootstrap must remain on-device and self-service.',
      );
    }
    _rejectBootstrapSecrets(map);
    for (final key in [
      'normalOperationRequiresDesktop',
      'adbRequiredForNormalOperation',
      'rootRequired',
      'bootloaderUnlockRequired',
      'deviceOwnerRequiredForNormalOperation',
    ]) {
      if (_bootstrapBool(map, key)) {
        throw FormatException('$key must remain false.');
      }
    }
    if (_bootstrapString(map, 'developmentBridgePolicy') !=
        'optional_recovery_only') {
      throw const FormatException(
        'Development bridge must remain optional recovery only.',
      );
    }
    if (!_bootstrapBool(map, 'protectedAppReauthenticationRequired') ||
        _bootstrapString(map, 'protectedAppAccessPolicy') !=
            'deny_private_app_data_and_credentials') {
      throw const FormatException(
        'Protected-app bootstrap boundaries must remain fail-closed.',
      );
    }

    final setupSteps = _bootstrapList(map['setupSteps'], 'setupSteps');
    final recoveryPaths = _bootstrapList(map['recoveryPaths'], 'recoveryPaths');
    final stepIds = <String>{};
    for (final step in setupSteps) {
      final id = _bootstrapString(step, 'id');
      if (!stepIds.add(id)) {
        throw FormatException('Duplicate provisioning step: $id');
      }
      _bootstrapString(step, 'authority');
      _bootstrapString(step, 'state');
      _bootstrapBool(step, 'normalOperationDependency');
    }
    const requiredSteps = {
      'app_installation',
      'in_app_authentication',
      'android_roles_and_permissions',
      'oem_background_reliability',
    };
    if (!stepIds.containsAll(requiredSteps)) {
      throw const FormatException(
        'Provisioning bootstrap is missing required steps.',
      );
    }

    Map<String, Object?>? adbRecovery;
    for (final path in recoveryPaths) {
      final id = _bootstrapString(path, 'id');
      _bootstrapString(path, 'authority');
      if (_bootstrapBool(path, 'normalOperationDependency')) {
        throw FormatException('$id cannot be a normal-operation dependency.');
      }
      if (id == 'adb_development_bridge') adbRecovery = path;
    }
    if (adbRecovery == null ||
        _bootstrapString(adbRecovery, 'authority') != 'development_only') {
      throw const FormatException(
        'ADB must exist only as a development/recovery path.',
      );
    }
    final readiness = _bootstrapString(map, 'readiness');
    if (readiness != 'ready_for_on_device_enrollment' &&
        readiness != 'blocked') {
      throw FormatException('Unsupported provisioning readiness: $readiness');
    }

    return PandoraProvisioningBootstrap(
      readiness: readiness,
      deviceOwnerProvisioned: _bootstrapBool(map, 'deviceOwnerProvisioned'),
      homeRoleHeld: _bootstrapBool(map, 'homeRoleHeld'),
      setupSteps: setupSteps,
      recoveryPaths: recoveryPaths,
    );
  }
}

class PandoraProvisioningBootstrapRuntime {
  PandoraProvisioningBootstrapRuntime({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PandoraProvisioningBootstrap> getBootstrap() async {
    final raw = await _channel.invokeMethod<Object?>(
      'getProvisioningBootstrap',
    );
    return PandoraProvisioningBootstrap.fromMap(raw);
  }
}
