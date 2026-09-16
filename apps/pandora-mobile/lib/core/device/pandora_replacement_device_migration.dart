import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

Map<String, Object?> _map(Object? raw, String label) {
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

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String _identifier(Map<String, Object?> map, String key) {
  final value = _string(map, key);
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw FormatException('$key must be a bounded identifier.');
  }
  return value;
}

bool _bool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

void _exactKeys(Map<String, Object?> map, Set<String> allowed, String label) {
  final extras = map.keys.where((key) => !allowed.contains(key)).toList();
  final missing = allowed.where((key) => !map.containsKey(key)).toList();
  if (extras.isNotEmpty || missing.isNotEmpty) {
    throw FormatException('$label has unsupported or missing fields.');
  }
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Migration payload keys must be strings.');
      }
      sorted[entry.key as String] = _canonical(entry.value);
    }
    return sorted;
  }
  if (value is List) return value.map(_canonical).toList(growable: false);
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException('Migration payload contains unsupported data.');
}

class PandoraMigrationMemoryRef {
  const PandoraMigrationMemoryRef({
    required this.recordId,
    required this.recordType,
    required this.revision,
  });

  final String recordId;
  final String recordType;
  final int revision;

  factory PandoraMigrationMemoryRef.fromMap(Object? raw) {
    final map = _map(raw, 'memory reference');
    _exactKeys(map, {'recordId', 'recordType', 'revision'}, 'memory reference');
    const allowedTypes = {
      'fact',
      'pattern',
      'procedure',
      'failure_lesson',
      'outcome',
      'provider_performance',
    };
    final type = _string(map, 'recordType');
    final revision = map['revision'];
    if (!allowedTypes.contains(type) || revision is! int || revision < 1) {
      throw const FormatException('Invalid portable Memory reference.');
    }
    return PandoraMigrationMemoryRef(
      recordId: _identifier(map, 'recordId'),
      recordType: type,
      revision: revision,
    );
  }
}

class PandoraMigrationPolicyRef {
  const PandoraMigrationPolicyRef({
    required this.policyId,
    required this.authorizationFingerprint,
  });

  final String policyId;
  final String authorizationFingerprint;

  factory PandoraMigrationPolicyRef.fromMap(Object? raw) {
    final map = _map(raw, 'policy reference');
    _exactKeys(
      map,
      {
        'policyId',
        'authorizationFingerprint',
        'statusAtExport',
        'requiresRevalidation'
      },
      'policy reference',
    );
    final fingerprint = _string(map, 'authorizationFingerprint');
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(fingerprint) ||
        _string(map, 'statusAtExport') != 'active' ||
        !_bool(map, 'requiresRevalidation')) {
      throw const FormatException(
          'Policy reference must require active revalidation.');
    }
    return PandoraMigrationPolicyRef(
      policyId: _identifier(map, 'policyId'),
      authorizationFingerprint: fingerprint.toLowerCase(),
    );
  }
}

class PandoraReplacementDeviceMigrationBundle {
  const PandoraReplacementDeviceMigrationBundle({
    required this.migrationId,
    required this.subjectUserId,
    required this.createdAt,
    required this.payloadSha256,
    required this.memoryRefs,
    required this.policyRefs,
    required this.preferredCapabilities,
  });

  final String migrationId;
  final String subjectUserId;
  final DateTime createdAt;
  final String payloadSha256;
  final List<PandoraMigrationMemoryRef> memoryRefs;
  final List<PandoraMigrationPolicyRef> policyRefs;
  final List<String> preferredCapabilities;

  static String computePayloadSha256(Map<String, Object?> payload) {
    return sha256
        .convert(utf8.encode(jsonEncode(_canonical(payload))))
        .toString();
  }

  factory PandoraReplacementDeviceMigrationBundle.fromMap(Object? raw) {
    final map = _map(raw, 'replacement-device migration bundle');
    _exactKeys(
      map,
      {'schemaVersion', 'integrityAlgorithm', 'payloadSha256', 'payload'},
      'replacement-device migration bundle',
    );
    if (_string(map, 'schemaVersion') !=
            'pandora-replacement-device-migration-v1' ||
        _string(map, 'integrityAlgorithm') != 'sha256') {
      throw const FormatException(
          'Unsupported replacement-device migration schema.');
    }
    final payload = _map(map['payload'], 'migration payload');
    _exactKeys(
      payload,
      {
        'migrationId',
        'subjectUserId',
        'createdAt',
        'exportMode',
        'requiresUserReauthentication',
        'protectedAppReauthenticationRequired',
        'discardDeviceLocalRecoveryHints',
        'memoryRefs',
        'policyRefs',
        'capabilityConfig',
      },
      'migration payload',
    );
    if (_string(payload, 'exportMode') != 'portable_state_only' ||
        !_bool(payload, 'requiresUserReauthentication') ||
        !_bool(payload, 'protectedAppReauthenticationRequired') ||
        !_bool(payload, 'discardDeviceLocalRecoveryHints')) {
      throw const FormatException(
          'Migration must remain portable and reauthentication-bound.');
    }
    final expectedDigest = _string(map, 'payloadSha256').toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedDigest) ||
        computePayloadSha256(payload) != expectedDigest) {
      throw const FormatException('Migration payload integrity check failed.');
    }
    final createdAt = DateTime.tryParse(_string(payload, 'createdAt'))?.toUtc();
    if (createdAt == null) {
      throw const FormatException('Invalid migration creation time.');
    }

    final memoryRaw = payload['memoryRefs'];
    final policyRaw = payload['policyRefs'];
    if (memoryRaw is! List || policyRaw is! List) {
      throw const FormatException('Migration references must be lists.');
    }
    final memoryRefs = memoryRaw
        .map(PandoraMigrationMemoryRef.fromMap)
        .toList(growable: false);
    final policyRefs = policyRaw
        .map(PandoraMigrationPolicyRef.fromMap)
        .toList(growable: false);
    if (memoryRefs.map((item) => item.recordId).toSet().length !=
            memoryRefs.length ||
        policyRefs.map((item) => item.policyId).toSet().length !=
            policyRefs.length) {
      throw const FormatException('Migration references must be unique.');
    }

    final capability = _map(payload['capabilityConfig'], 'capability config');
    _exactKeys(
      capability,
      {
        'preferredCapabilities',
        'refreshCompatibilityProfile',
        'refreshOemAdapter',
        'restoreMeasuredHardwareFacts',
        'restoreAndroidRoles',
        'restoreRuntimePermissions',
      },
      'capability config',
    );
    if (!_bool(capability, 'refreshCompatibilityProfile') ||
        !_bool(capability, 'refreshOemAdapter') ||
        _bool(capability, 'restoreMeasuredHardwareFacts') ||
        _bool(capability, 'restoreAndroidRoles') ||
        _bool(capability, 'restoreRuntimePermissions')) {
      throw const FormatException(
          'New-device capability truth must be freshly discovered.');
    }
    final preferredRaw = capability['preferredCapabilities'];
    if (preferredRaw is! List ||
        preferredRaw.any((value) => value is! String)) {
      throw const FormatException(
          'preferredCapabilities must be a string list.');
    }
    final preferred = preferredRaw
        .map((value) => (value as String).trim())
        .toList(growable: false);
    if (preferred.any((value) =>
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) ||
        preferred.toSet().length != preferred.length) {
      throw const FormatException(
          'preferredCapabilities must be unique and non-empty.');
    }
    return PandoraReplacementDeviceMigrationBundle(
      migrationId: _identifier(payload, 'migrationId'),
      subjectUserId: _identifier(payload, 'subjectUserId'),
      createdAt: createdAt,
      payloadSha256: expectedDigest,
      memoryRefs: List.unmodifiable(memoryRefs),
      policyRefs: List.unmodifiable(policyRefs),
      preferredCapabilities: List.unmodifiable(preferred),
    );
  }
}

class PandoraReplacementDeviceMigrationPlan {
  const PandoraReplacementDeviceMigrationPlan._({
    required this.bundle,
    required this.idempotencyKey,
  });

  final PandoraReplacementDeviceMigrationBundle bundle;
  final String idempotencyKey;

  factory PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser({
    required PandoraReplacementDeviceMigrationBundle bundle,
    required String authenticatedUserId,
  }) {
    final userId = authenticatedUserId.trim();
    if (userId.isEmpty || userId != bundle.subjectUserId) {
      throw const FormatException(
          'Migration bundle does not belong to the authenticated user.');
    }
    return PandoraReplacementDeviceMigrationPlan._(
      bundle: bundle,
      idempotencyKey: 'm8-004:${bundle.migrationId}:${bundle.payloadSha256}',
    );
  }
}

abstract interface class PandoraMigrationMemoryPort {
  Future<void> refetch(PandoraMigrationMemoryRef reference);
}

abstract interface class PandoraMigrationPolicyPort {
  Future<bool> revalidate(PandoraMigrationPolicyRef reference);
}

abstract interface class PandoraMigrationCapabilityPort {
  Future<List<String>> readPreferredCapabilities();
  Future<void> writePreferredCapabilities(List<String> capabilities);
  Future<void> refreshCompatibilityAndOemTruth();
}

abstract interface class PandoraMigrationReceiptStore {
  Future<String?> readDigest(String migrationId);
  Future<void> writeDigest(String migrationId, String payloadSha256);
}

class PandoraReplacementDeviceMigrationReceipt {
  const PandoraReplacementDeviceMigrationReceipt({
    required this.alreadyApplied,
    required this.memoryReferenceCount,
    required this.policyReferenceCount,
  });

  final bool alreadyApplied;
  final int memoryReferenceCount;
  final int policyReferenceCount;
}

class PandoraReplacementDeviceMigrationExecutor {
  PandoraReplacementDeviceMigrationExecutor({
    required PandoraMigrationMemoryPort memory,
    required PandoraMigrationPolicyPort policies,
    required PandoraMigrationCapabilityPort capabilities,
    required PandoraMigrationReceiptStore receipts,
  })  : _memory = memory,
        _policies = policies,
        _capabilities = capabilities,
        _receipts = receipts;

  final PandoraMigrationMemoryPort _memory;
  final PandoraMigrationPolicyPort _policies;
  final PandoraMigrationCapabilityPort _capabilities;
  final PandoraMigrationReceiptStore _receipts;

  Future<PandoraReplacementDeviceMigrationReceipt> execute(
    PandoraReplacementDeviceMigrationPlan plan,
  ) async {
    final bundle = plan.bundle;
    final previous = await _receipts.readDigest(bundle.migrationId);
    if (previous == bundle.payloadSha256) {
      return PandoraReplacementDeviceMigrationReceipt(
        alreadyApplied: true,
        memoryReferenceCount: bundle.memoryRefs.length,
        policyReferenceCount: bundle.policyRefs.length,
      );
    }
    if (previous != null) {
      throw StateError(
          'Migration identity already exists with different content.');
    }

    for (final policy in bundle.policyRefs) {
      if (!await _policies.revalidate(policy)) {
        throw StateError(
            'A standing policy is no longer valid on the replacement device.');
      }
    }
    final priorCapabilities = await _capabilities.readPreferredCapabilities();
    try {
      for (final memory in bundle.memoryRefs) {
        await _memory.refetch(memory);
      }
      await _capabilities
          .writePreferredCapabilities(bundle.preferredCapabilities);
      await _capabilities.refreshCompatibilityAndOemTruth();
      await _receipts.writeDigest(bundle.migrationId, bundle.payloadSha256);
    } catch (_) {
      await _capabilities.writePreferredCapabilities(priorCapabilities);
      rethrow;
    }
    return PandoraReplacementDeviceMigrationReceipt(
      alreadyApplied: false,
      memoryReferenceCount: bundle.memoryRefs.length,
      policyReferenceCount: bundle.policyRefs.length,
    );
  }
}
