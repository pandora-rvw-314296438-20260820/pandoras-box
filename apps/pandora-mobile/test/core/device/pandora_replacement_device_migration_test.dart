import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/device/pandora_replacement_device_migration.dart';

Map<String, Object?> _payload() => {
      'migrationId': 'migration-001',
      'subjectUserId': 'user-123',
      'createdAt': '2026-09-15T07:20:00Z',
      'exportMode': 'portable_state_only',
      'requiresUserReauthentication': true,
      'protectedAppReauthenticationRequired': true,
      'discardDeviceLocalRecoveryHints': true,
      'memoryRefs': [
        {'recordId': 'memory-1', 'recordType': 'fact', 'revision': 3},
        {'recordId': 'memory-2', 'recordType': 'procedure', 'revision': 1},
      ],
      'policyRefs': [
        {
          'policyId': 'policy-1',
          'authorizationFingerprint': 'a' * 64,
          'statusAtExport': 'active',
          'requiresRevalidation': true,
        },
      ],
      'capabilityConfig': {
        'preferredCapabilities': ['contacts', 'sms'],
        'refreshCompatibilityProfile': true,
        'refreshOemAdapter': true,
        'restoreMeasuredHardwareFacts': false,
        'restoreAndroidRoles': false,
        'restoreRuntimePermissions': false,
      },
    };

Map<String, Object?> _bundle([Map<String, Object?>? payload]) {
  final body = payload ?? _payload();
  return {
    'schemaVersion': 'pandora-replacement-device-migration-v1',
    'integrityAlgorithm': 'sha256',
    'payloadSha256':
        PandoraReplacementDeviceMigrationBundle.computePayloadSha256(body),
    'payload': body,
  };
}

class _MemoryPort implements PandoraMigrationMemoryPort {
  final restored = <String>[];
  bool fail = false;

  @override
  Future<void> refetch(PandoraMigrationMemoryRef reference) async {
    if (fail) throw StateError('memory unavailable');
    restored.add(reference.recordId);
  }
}

class _PolicyPort implements PandoraMigrationPolicyPort {
  bool valid = true;
  final checked = <String>[];

  @override
  Future<bool> revalidate(PandoraMigrationPolicyRef reference) async {
    checked.add(reference.policyId);
    return valid;
  }
}

class _CapabilityPort implements PandoraMigrationCapabilityPort {
  List<String> current = ['camera'];
  int refreshes = 0;
  bool failRefresh = false;
  final writes = <List<String>>[];

  @override
  Future<List<String>> readPreferredCapabilities() async => List.of(current);

  @override
  Future<void> writePreferredCapabilities(List<String> capabilities) async {
    current = List.of(capabilities);
    writes.add(List.of(capabilities));
  }

  @override
  Future<void> refreshCompatibilityAndOemTruth() async {
    refreshes += 1;
    if (failRefresh) throw StateError('profile refresh failed');
  }
}

class _ReceiptStore implements PandoraMigrationReceiptStore {
  final values = <String, String>{};
  int writes = 0;

  @override
  Future<String?> readDigest(String migrationId) async => values[migrationId];

  @override
  Future<void> writeDigest(String migrationId, String payloadSha256) async {
    values[migrationId] = payloadSha256;
    writes += 1;
  }
}

void main() {
  test('parses a portable replacement-device bundle with verified integrity',
      () {
    final parsed = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    expect(parsed.migrationId, 'migration-001');
    expect(parsed.subjectUserId, 'user-123');
    expect(parsed.memoryRefs.length, 2);
    expect(parsed.policyRefs.single.policyId, 'policy-1');
    expect(parsed.preferredCapabilities, ['contacts', 'sms']);
  });

  test('rejects payload tampering after digest creation', () {
    final encoded = _bundle();
    final payload = Map<String, Object?>.from(encoded['payload']! as Map);
    payload['subjectUserId'] = 'attacker';
    encoded['payload'] = payload;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(encoded),
      throwsFormatException,
    );
  });

  test('rejects secret-shaped or unknown migration fields fail closed', () {
    for (final forbidden in ['accessToken', 'password', 'otp', 'keystore']) {
      final payload = _payload()..[forbidden] = 'not-allowed';
      expect(
        () => PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(payload)),
        throwsFormatException,
        reason: forbidden,
      );
    }
  });

  test('requires reauthentication and refuses copied runtime authority', () {
    for (final key in [
      'requiresUserReauthentication',
      'protectedAppReauthenticationRequired',
      'discardDeviceLocalRecoveryHints',
    ]) {
      final payload = _payload()..[key] = false;
      expect(
        () => PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(payload)),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('requires fresh hardware OEM roles and permission discovery', () {
    final cases = <String, Object?>{
      'refreshCompatibilityProfile': false,
      'refreshOemAdapter': false,
      'restoreMeasuredHardwareFacts': true,
      'restoreAndroidRoles': true,
      'restoreRuntimePermissions': true,
    };
    for (final entry in cases.entries) {
      final payload = _payload();
      final config =
          Map<String, Object?>.from(payload['capabilityConfig']! as Map)
            ..[entry.key] = entry.value;
      payload['capabilityConfig'] = config;
      expect(
        () => PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(payload)),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });

  test('does not accept stale or non-revalidated standing policy authority',
      () {
    final stale = _payload();
    final stalePolicies =
        List<Map<String, Object?>>.from(stale['policyRefs']! as List);
    stalePolicies[0] = Map<String, Object?>.from(stalePolicies[0])
      ..['statusAtExport'] = 'revoked';
    stale['policyRefs'] = stalePolicies;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(stale)),
      throwsFormatException,
    );

    final unverified = _payload();
    final policies =
        List<Map<String, Object?>>.from(unverified['policyRefs']! as List);
    policies[0] = Map<String, Object?>.from(policies[0])
      ..['requiresRevalidation'] = false;
    unverified['policyRefs'] = policies;
    expect(
      () =>
          PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(unverified)),
      throwsFormatException,
    );
  });

  test('binds restore plan to the freshly authenticated owner', () {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    expect(
      () => PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
        bundle: bundle,
        authenticatedUserId: 'someone-else',
      ),
      throwsFormatException,
    );
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    expect(plan.idempotencyKey, startsWith('m8-004:migration-001:'));
  });

  test(
      'migration drill refetches Memory, revalidates policy and refreshes device truth',
      () async {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    final memory = _MemoryPort();
    final policies = _PolicyPort();
    final capabilities = _CapabilityPort();
    final receipts = _ReceiptStore();
    final executor = PandoraReplacementDeviceMigrationExecutor(
      memory: memory,
      policies: policies,
      capabilities: capabilities,
      receipts: receipts,
    );

    final receipt = await executor.execute(plan);
    expect(receipt.alreadyApplied, isFalse);
    expect(memory.restored, ['memory-1', 'memory-2']);
    expect(policies.checked, ['policy-1']);
    expect(capabilities.current, ['contacts', 'sms']);
    expect(capabilities.refreshes, 1);
    expect(receipts.writes, 1);
  });

  test('replay is idempotent and produces no duplicate restore side effects',
      () async {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    final memory = _MemoryPort();
    final policies = _PolicyPort();
    final capabilities = _CapabilityPort();
    final receipts = _ReceiptStore();
    final executor = PandoraReplacementDeviceMigrationExecutor(
      memory: memory,
      policies: policies,
      capabilities: capabilities,
      receipts: receipts,
    );

    await executor.execute(plan);
    final second = await executor.execute(plan);
    expect(second.alreadyApplied, isTrue);
    expect(memory.restored, ['memory-1', 'memory-2']);
    expect(policies.checked, ['policy-1']);
    expect(capabilities.refreshes, 1);
    expect(receipts.writes, 1);
  });

  test('policy revalidation fails before any restored state mutation',
      () async {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    final memory = _MemoryPort();
    final policies = _PolicyPort()..valid = false;
    final capabilities = _CapabilityPort();
    final receipts = _ReceiptStore();
    final executor = PandoraReplacementDeviceMigrationExecutor(
      memory: memory,
      policies: policies,
      capabilities: capabilities,
      receipts: receipts,
    );

    await expectLater(executor.execute(plan), throwsStateError);
    expect(memory.restored, isEmpty);
    expect(capabilities.writes, isEmpty);
    expect(receipts.writes, 0);
  });

  test('failed device-truth refresh rolls portable preferences back', () async {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    final memory = _MemoryPort();
    final policies = _PolicyPort();
    final capabilities = _CapabilityPort()..failRefresh = true;
    final receipts = _ReceiptStore();
    final executor = PandoraReplacementDeviceMigrationExecutor(
      memory: memory,
      policies: policies,
      capabilities: capabilities,
      receipts: receipts,
    );

    await expectLater(executor.execute(plan), throwsStateError);
    expect(capabilities.current, ['camera']);
    expect(capabilities.writes.last, ['camera']);
    expect(receipts.writes, 0);
  });

  test('same migration identity with different applied digest fails closed',
      () async {
    final bundle = PandoraReplacementDeviceMigrationBundle.fromMap(_bundle());
    final plan = PandoraReplacementDeviceMigrationPlan.forAuthenticatedUser(
      bundle: bundle,
      authenticatedUserId: 'user-123',
    );
    final receipts = _ReceiptStore()..values['migration-001'] = 'b' * 64;
    final executor = PandoraReplacementDeviceMigrationExecutor(
      memory: _MemoryPort(),
      policies: _PolicyPort(),
      capabilities: _CapabilityPort(),
      receipts: receipts,
    );
    await expectLater(executor.execute(plan), throwsStateError);
  });
  test('rejects unbounded identifiers in portable references and preferences',
      () {
    final badMigration = _payload()..['migrationId'] = 'bad migration id';
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(
          _bundle(badMigration)),
      throwsFormatException,
    );

    final badMemory = _payload();
    final refs =
        List<Map<String, Object?>>.from(badMemory['memoryRefs']! as List);
    refs[0] = Map<String, Object?>.from(refs[0])..['recordId'] = 'x' * 129;
    badMemory['memoryRefs'] = refs;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(_bundle(badMemory)),
      throwsFormatException,
    );

    final badCapability = _payload();
    final config =
        Map<String, Object?>.from(badCapability['capabilityConfig']! as Map)
          ..['preferredCapabilities'] = ['contacts', 'bad capability'];
    badCapability['capabilityConfig'] = config;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(
          _bundle(badCapability)),
      throwsFormatException,
    );
  });

  test('rejects duplicate Memory and policy references', () {
    final duplicateMemory = _payload();
    final memoryRefs =
        List<Map<String, Object?>>.from(duplicateMemory['memoryRefs']! as List)
          ..add(Map<String, Object?>.from(
              (duplicateMemory['memoryRefs']! as List).first as Map));
    duplicateMemory['memoryRefs'] = memoryRefs;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(
          _bundle(duplicateMemory)),
      throwsFormatException,
    );

    final duplicatePolicy = _payload();
    final policyRefs =
        List<Map<String, Object?>>.from(duplicatePolicy['policyRefs']! as List)
          ..add(Map<String, Object?>.from(
              (duplicatePolicy['policyRefs']! as List).first as Map));
    duplicatePolicy['policyRefs'] = policyRefs;
    expect(
      () => PandoraReplacementDeviceMigrationBundle.fromMap(
          _bundle(duplicatePolicy)),
      throwsFormatException,
    );
  });
}
