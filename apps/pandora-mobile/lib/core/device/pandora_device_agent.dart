import 'package:flutter/services.dart';

enum PandoraDeviceAuthority {
  publicApp,
  runtimePermission,
  androidRole,
  deviceOwner,
  developmentOnly,
  policyDenied,
}

enum PandoraDeviceAvailability {
  available,
  unsupported,
  permissionRequired,
  implementationPending,
  forbidden,
}

PandoraDeviceAuthority _parseAuthority(Object? value) {
  return switch (value) {
    'public_app' => PandoraDeviceAuthority.publicApp,
    'runtime_permission' => PandoraDeviceAuthority.runtimePermission,
    'android_role' => PandoraDeviceAuthority.androidRole,
    'device_owner' => PandoraDeviceAuthority.deviceOwner,
    'development_only' => PandoraDeviceAuthority.developmentOnly,
    'policy_denied' => PandoraDeviceAuthority.policyDenied,
    _ => throw FormatException('Unknown device authority: $value'),
  };
}

PandoraDeviceAvailability _parseAvailability(Object? value) {
  return switch (value) {
    'available' => PandoraDeviceAvailability.available,
    'unsupported' => PandoraDeviceAvailability.unsupported,
    'permission_required' => PandoraDeviceAvailability.permissionRequired,
    'implementation_pending' => PandoraDeviceAvailability.implementationPending,
    'forbidden' => PandoraDeviceAvailability.forbidden,
    _ => throw FormatException('Unknown device availability: $value'),
  };
}

Map<String, Object?> _stringMap(Object? raw, String label) {
  if (raw is! Map) {
    throw FormatException('$label must be a map.');
  }
  final result = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    result[key] = entry.value;
  }
  return result;
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

class PandoraDeviceCapability {
  const PandoraDeviceCapability({
    required this.id,
    required this.authority,
    required this.availability,
    required this.reason,
    required this.normalOperationDependency,
  });

  final String id;
  final PandoraDeviceAuthority authority;
  final PandoraDeviceAvailability availability;
  final String reason;
  final bool normalOperationDependency;

  factory PandoraDeviceCapability.fromMap(Object? raw) {
    final map = _stringMap(raw, 'device capability');
    final authority = _parseAuthority(map['authority']);
    final availability = _parseAvailability(map['availability']);
    final normalOperationDependency = _requiredBool(
      map,
      'normalOperationDependency',
    );

    if (availability == PandoraDeviceAvailability.forbidden &&
        authority != PandoraDeviceAuthority.policyDenied) {
      throw const FormatException(
        'Forbidden capabilities must use policy_denied authority.',
      );
    }
    if (normalOperationDependency &&
        (authority == PandoraDeviceAuthority.developmentOnly ||
            authority == PandoraDeviceAuthority.policyDenied)) {
      throw const FormatException(
        'Development-only or policy-denied capabilities cannot be normal-operation dependencies.',
      );
    }

    return PandoraDeviceCapability(
      id: _requiredString(map, 'id'),
      authority: authority,
      availability: availability,
      reason: _requiredString(map, 'reason'),
      normalOperationDependency: normalOperationDependency,
    );
  }
}

class PandoraDeviceCapabilityManifest {
  const PandoraDeviceCapabilityManifest({
    required this.schemaVersion,
    required this.platform,
    required this.adapterId,
    required this.sdkInt,
    required this.deviceOwnerProvisioned,
    required this.normalOperationRequiresDesktop,
    required this.rootRequired,
    required this.bootloaderUnlockRequired,
    required this.protectedAppAccessPolicy,
    required this.developmentBridgePolicy,
    required this.capabilities,
  });

  final String schemaVersion;
  final String platform;
  final String adapterId;
  final int sdkInt;
  final bool deviceOwnerProvisioned;
  final bool normalOperationRequiresDesktop;
  final bool rootRequired;
  final bool bootloaderUnlockRequired;
  final String protectedAppAccessPolicy;
  final String developmentBridgePolicy;
  final List<PandoraDeviceCapability> capabilities;

  PandoraDeviceCapability? capability(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability;
    }
    return null;
  }

  factory PandoraDeviceCapabilityManifest.fromMap(Object? raw) {
    final map = _stringMap(raw, 'device capability manifest');
    final schemaVersion = _requiredString(map, 'schemaVersion');
    if (schemaVersion != '1.0.0') {
      throw FormatException(
        'Unsupported device capability schema: $schemaVersion',
      );
    }
    final platform = _requiredString(map, 'platform');
    if (platform != 'android') {
      throw FormatException('Unsupported device platform: $platform');
    }

    final normalOperationRequiresDesktop = _requiredBool(
      map,
      'normalOperationRequiresDesktop',
    );
    final rootRequired = _requiredBool(map, 'rootRequired');
    final bootloaderUnlockRequired = _requiredBool(
      map,
      'bootloaderUnlockRequired',
    );
    if (normalOperationRequiresDesktop) {
      throw const FormatException(
        'Normal Pandora operation must not require a desktop.',
      );
    }
    if (rootRequired || bootloaderUnlockRequired) {
      throw const FormatException(
        'Pandora Device Agent must not require root or bootloader unlock.',
      );
    }

    final protectedAppAccessPolicy = _requiredString(
      map,
      'protectedAppAccessPolicy',
    );
    if (protectedAppAccessPolicy != 'deny_private_app_data_and_credentials') {
      throw const FormatException(
        'Protected-app access policy is not fail-closed.',
      );
    }
    final developmentBridgePolicy = _requiredString(
      map,
      'developmentBridgePolicy',
    );
    if (developmentBridgePolicy != 'optional_not_trust_dependency') {
      throw const FormatException(
        'Development bridge must remain optional and outside the trust root.',
      );
    }

    final rawCapabilities = map['capabilities'];
    if (rawCapabilities is! List) {
      throw const FormatException('capabilities must be a list.');
    }
    final capabilities = rawCapabilities
        .map(PandoraDeviceCapability.fromMap)
        .toList(growable: false);
    final ids = <String>{};
    for (final capability in capabilities) {
      if (!ids.add(capability.id)) {
        throw FormatException(
          'Duplicate device capability id: ${capability.id}',
        );
      }
    }

    final deviceOwnerProvisioned = _requiredBool(map, 'deviceOwnerProvisioned');
    if (!deviceOwnerProvisioned &&
        capabilities.any(
          (capability) =>
              capability.authority == PandoraDeviceAuthority.deviceOwner &&
              capability.availability == PandoraDeviceAvailability.available,
        )) {
      throw const FormatException(
        'Device Owner capability cannot be available when Device Owner is not provisioned.',
      );
    }

    return PandoraDeviceCapabilityManifest(
      schemaVersion: schemaVersion,
      platform: platform,
      adapterId: _requiredString(map, 'adapterId'),
      sdkInt: _requiredInt(map, 'sdkInt'),
      deviceOwnerProvisioned: deviceOwnerProvisioned,
      normalOperationRequiresDesktop: normalOperationRequiresDesktop,
      rootRequired: rootRequired,
      bootloaderUnlockRequired: bootloaderUnlockRequired,
      protectedAppAccessPolicy: protectedAppAccessPolicy,
      developmentBridgePolicy: developmentBridgePolicy,
      capabilities: List.unmodifiable(capabilities),
    );
  }
}

class PandoraPermissionState {
  const PandoraPermissionState({
    required this.permission,
    required this.declared,
    required this.granted,
  });

  final String permission;
  final bool declared;
  final bool granted;

  factory PandoraPermissionState.fromMap(Object? raw) {
    final map = _stringMap(raw, 'permission state');
    return PandoraPermissionState(
      permission: _requiredString(map, 'permission'),
      declared: _requiredBool(map, 'declared'),
      granted: _requiredBool(map, 'granted'),
    );
  }
}

enum PandoraSafeDiagnosticKind { capabilityManifest, permissionState }

class PandoraSafeDiagnosticRequest {
  const PandoraSafeDiagnosticRequest(this.kind);

  final PandoraSafeDiagnosticKind kind;

  Map<String, Object?> toMap() => {
    'kind': switch (kind) {
      PandoraSafeDiagnosticKind.capabilityManifest => 'capability_manifest',
      PandoraSafeDiagnosticKind.permissionState => 'permission_state',
    },
  };
}

class PandoraSafeDiagnosticResult {
  const PandoraSafeDiagnosticResult({
    required this.kind,
    required this.status,
    required this.result,
  });

  final PandoraSafeDiagnosticKind kind;
  final String status;
  final Object? result;

  factory PandoraSafeDiagnosticResult.fromMap(Object? raw) {
    final map = _stringMap(raw, 'diagnostic result');
    final kind = switch (_requiredString(map, 'kind')) {
      'capability_manifest' => PandoraSafeDiagnosticKind.capabilityManifest,
      'permission_state' => PandoraSafeDiagnosticKind.permissionState,
      final value => throw FormatException(
        'Unknown safe diagnostic result kind: $value',
      ),
    };
    final status = _requiredString(map, 'status');
    if (status != 'completed') {
      throw FormatException('Unknown safe diagnostic status: $status');
    }
    return PandoraSafeDiagnosticResult(
      kind: kind,
      status: status,
      result: map['result'],
    );
  }
}

abstract interface class PandoraDeviceAgent {
  Future<PandoraDeviceCapabilityManifest> getCapabilityManifest();

  Future<List<PandoraPermissionState>> getPermissionStates();

  Future<PandoraSafeDiagnosticResult> runSafeDiagnostic(
    PandoraSafeDiagnosticRequest request,
  );
}

class MethodChannelPandoraDeviceAgent implements PandoraDeviceAgent {
  MethodChannelPandoraDeviceAgent({
    MethodChannel channel = const MethodChannel('pandora/device_agent'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<PandoraDeviceCapabilityManifest> getCapabilityManifest() async {
    final raw = await _channel.invokeMethod<Object?>('getCapabilityManifest');
    return PandoraDeviceCapabilityManifest.fromMap(raw);
  }

  @override
  Future<List<PandoraPermissionState>> getPermissionStates() async {
    final raw = await _channel.invokeMethod<Object?>('getPermissionStates');
    if (raw is! List) {
      throw const FormatException('permission states must be a list.');
    }
    return List.unmodifiable(raw.map(PandoraPermissionState.fromMap));
  }

  @override
  Future<PandoraSafeDiagnosticResult> runSafeDiagnostic(
    PandoraSafeDiagnosticRequest request,
  ) async {
    final raw = await _channel.invokeMethod<Object?>(
      'runSafeDiagnostic',
      request.toMap(),
    );
    return PandoraSafeDiagnosticResult.fromMap(raw);
  }
}
