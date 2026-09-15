import 'package:flutter/services.dart';

Map<String, Object?> _profileMap(Object? raw, String label) {
  if (raw is! Map) throw FormatException('$label must be a map.');
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

String _profileString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _profileBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

num? _nullableNonNegative(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('$key must be null or a non-negative number.');
  }
  return value;
}

void _rejectProfileIdentifiers(Map<String, Object?> map) {
  const forbidden = {
    'androidId',
    'serial',
    'imei',
    'imsi',
    'ssid',
    'bssid',
    'ipAddress',
    'ipAddresses',
    'macAddress',
  };
  void walk(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String && forbidden.contains(entry.key)) {
          throw const FormatException(
            'Compatibility profile must not contain device or network identifiers.',
          );
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

class PandoraDeviceCompatibilityProfile {
  const PandoraDeviceCompatibilityProfile({
    required this.sdkInt,
    required this.cpu,
    required this.memory,
    required this.storage,
    required this.accelerators,
    required this.roles,
    required this.sensors,
    required this.oem,
    required this.constraints,
  });

  final int sdkInt;
  final Map<String, Object?> cpu;
  final Map<String, Object?> memory;
  final Map<String, Object?> storage;
  final Map<String, Object?> accelerators;
  final Map<String, Object?> roles;
  final Map<String, Object?> sensors;
  final Map<String, Object?> oem;
  final Map<String, Object?> constraints;

  factory PandoraDeviceCompatibilityProfile.fromMap(Object? raw) {
    final map = _profileMap(raw, 'device compatibility profile');
    if (_profileString(map, 'schemaVersion') != '1.0.0') {
      throw const FormatException('Unsupported compatibility profile schema.');
    }
    if (_profileString(map, 'platform') != 'android') {
      throw const FormatException('Compatibility profile must be Android.');
    }
    final sdkInt = map['sdkInt'];
    if (sdkInt is! int || sdkInt <= 0) {
      throw const FormatException('sdkInt must be a positive integer.');
    }
    _rejectProfileIdentifiers(map);

    final cpu = _profileMap(map['cpu'], 'cpu');
    final abis = cpu['supportedAbis'];
    if (abis is! List ||
        abis.isEmpty ||
        abis.any((value) => value is! String)) {
      throw const FormatException(
        'supportedAbis must be a non-empty string list.',
      );
    }
    final logicalProcessors = cpu['logicalProcessors'];
    if (logicalProcessors is! int || logicalProcessors <= 0) {
      throw const FormatException('logicalProcessors must be positive.');
    }

    final memory = _profileMap(map['memory'], 'memory');
    _nullableNonNegative(memory, 'totalBytes');
    final storage = _profileMap(map['storage'], 'storage');
    _nullableNonNegative(storage, 'totalBytes');
    _nullableNonNegative(storage, 'availableBytes');
    final accelerators = _profileMap(map['accelerators'], 'accelerators');
    final npu = _profileMap(accelerators['npu'], 'npu');
    if (_profileString(npu, 'availability') != 'unknown' ||
        _profileString(npu, 'evidence') != 'not_probed_by_stable_public_api') {
      throw const FormatException(
        'NPU availability must remain unknown until a stable verifier exists.',
      );
    }

    final roles = _profileMap(map['roles'], 'roles');
    _profileBool(roles, 'deviceOwnerProvisioned');
    _profileBool(roles, 'homeRoleHeld');
    _profileString(roles, 'dialerRoleAvailability');
    _profileString(roles, 'smsRoleAvailability');

    final sensors = _profileMap(map['sensors'], 'sensors');
    for (final key in [
      'cameraHardware',
      'microphoneHardware',
      'telephonyHardware',
      'bluetoothHardware',
      'hardwarePresenceOnly',
    ]) {
      _profileBool(sensors, key);
    }
    if (!_profileBool(sensors, 'hardwarePresenceOnly')) {
      throw const FormatException(
        'Sensor profile must not imply permission grants.',
      );
    }
    final oem = _profileMap(map['oem'], 'oem');
    _profileString(oem, 'adapterId');
    _profileString(oem, 'manufacturer');
    _profileString(oem, 'brand');
    _profileBool(oem, 'xiaomiFamily');
    _profileString(oem, 'autostartManagement');

    final constraints = _profileMap(map['constraints'], 'constraints');
    for (final key in [
      'normalOperationRequiresDesktop',
      'rootRequired',
      'bootloaderUnlockRequired',
      'hiddenOemApiRequired',
    ]) {
      if (_profileBool(constraints, key)) {
        throw FormatException('$key must remain false.');
      }
    }
    if (_profileString(constraints, 'protectedAppAccessPolicy') !=
        'deny_private_app_data_and_credentials') {
      throw const FormatException(
        'Protected-app policy must remain fail-closed.',
      );
    }
    if (_profileString(constraints, 'developmentBridgePolicy') !=
        'optional_not_trust_dependency') {
      throw const FormatException('Desktop bridge must remain optional.');
    }
    return PandoraDeviceCompatibilityProfile(
      sdkInt: sdkInt,
      cpu: Map.unmodifiable(cpu),
      memory: Map.unmodifiable(memory),
      storage: Map.unmodifiable(storage),
      accelerators: Map.unmodifiable(accelerators),
      roles: Map.unmodifiable(roles),
      sensors: Map.unmodifiable(sensors),
      oem: Map.unmodifiable(oem),
      constraints: Map.unmodifiable(constraints),
    );
  }
}

class PandoraDeviceCompatibilityRuntime {
  PandoraDeviceCompatibilityRuntime({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<PandoraDeviceCompatibilityProfile> getCompatibilityProfile() async {
    final raw = await _channel.invokeMethod<Object?>('getCompatibilityProfile');
    return PandoraDeviceCompatibilityProfile.fromMap(raw);
  }
}
