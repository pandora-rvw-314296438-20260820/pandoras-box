import 'pandora_local_data_policy.dart';
import 'pandora_local_store_contract.dart';

Future<PandoraLocalStore> openPandoraLocalStore() async {
  return MemoryPandoraLocalStore();
}

class MemoryPandoraLocalStore implements PandoraLocalStore {
  MemoryPandoraLocalStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, PandoraLocalCacheRecord> _cache = {};
  final Map<String, PandoraOfflineOperation> _operations = {};
  final Map<String, String> _idempotency = {};

  String _cacheId(PandoraLocalNamespace namespace, String key) {
    return '${namespace.name}:${requireLocalIdentifier(key, 'cache key')}';
  }

  @override
  Future<void> putCache({
    required PandoraLocalNamespace namespace,
    required String key,
    required Object? payload,
    required DateTime expiresAt,
    String? sourceRevision,
  }) async {
    final now = _clock().toUtc();
    PandoraLocalDataPolicy.validateExpiry(
      namespace: namespace,
      now: now,
      expiresAt: expiresAt,
    );
    final recordKey = requireLocalIdentifier(key, 'cache key');
    _cache[_cacheId(namespace, recordKey)] = PandoraLocalCacheRecord(
      namespace: namespace,
      key: recordKey,
      payloadJson: PandoraLocalDataPolicy.encodePayload(payload),
      updatedAt: now,
      expiresAt: expiresAt.toUtc(),
      sourceRevision: sourceRevision,
    );
  }

  @override
  Future<PandoraLocalCacheRecord?> getCache(
    PandoraLocalNamespace namespace,
    String key,
  ) async {
    final id = _cacheId(namespace, key);
    final record = _cache[id];
    if (record == null) return null;
    if (!record.expiresAt.isAfter(_clock().toUtc())) {
      _cache.remove(id);
      return null;
    }
    return record;
  }

  @override
  Future<void> deleteCache(PandoraLocalNamespace namespace, String key) async {
    _cache.remove(_cacheId(namespace, key));
  }

  @override
  Future<void> enqueue({
    required String operationId,
    required String idempotencyKey,
    required String capability,
    required Object? payload,
    required DateTime createdAt,
  }) async {
    final operation = requireLocalIdentifier(operationId, 'operation id');
    final key = requireLocalIdentifier(idempotencyKey, 'idempotency key');
    final boundedCapability = requireLocalIdentifier(capability, 'capability');
    final encoded = PandoraLocalDataPolicy.encodePayload(payload);
    final existingId = _idempotency[key];
    if (existingId != null) {
      final existing = _operations[existingId]!;
      if (existing.operationId != operation ||
          existing.capability != boundedCapability ||
          existing.payloadJson != encoded) {
        throw StateError(
          'Idempotency key already belongs to a different local operation.',
        );
      }
      return;
    }
    final created = createdAt.toUtc();
    _operations[operation] = PandoraOfflineOperation(
      operationId: operation,
      idempotencyKey: key,
      capability: boundedCapability,
      payloadJson: encoded,
      createdAt: created,
      nextAttemptAt: created,
    );
    _idempotency[key] = operation;
  }

  @override
  Future<List<PandoraOfflineOperation>> pendingOperations({
    required DateTime now,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final current = now.toUtc();
    final ready = _operations.values.where((operation) {
      return (operation.state == PandoraOfflineOperationState.pending ||
              operation.state == PandoraOfflineOperationState.retry) &&
          !operation.nextAttemptAt.isAfter(current);
    }).toList()
      ..sort((a, b) {
        final byCreated = a.createdAt.compareTo(b.createdAt);
        return byCreated != 0
            ? byCreated
            : a.operationId.compareTo(b.operationId);
      });
    return ready.take(limit).toList(growable: false);
  }

  PandoraOfflineOperation _active(String operationId) {
    final id = requireLocalIdentifier(operationId, 'operation id');
    final operation = _operations[id];
    if (operation == null ||
        (operation.state != PandoraOfflineOperationState.pending &&
            operation.state != PandoraOfflineOperationState.retry)) {
      throw StateError('Local operation is not active.');
    }
    return operation;
  }

  @override
  Future<void> markOperationRetry({
    required String operationId,
    required DateTime nextAttemptAt,
    required String errorCode,
  }) async {
    final operation = _active(operationId);
    _operations[operation.operationId] = operation.copyWith(
      state: PandoraOfflineOperationState.retry,
      attemptCount: operation.attemptCount + 1,
      nextAttemptAt: nextAttemptAt.toUtc(),
      lastErrorCode: requireLocalIdentifier(errorCode, 'error code'),
    );
  }

  @override
  Future<void> markOperationFailed({
    required String operationId,
    required String errorCode,
  }) async {
    final operation = _active(operationId);
    _operations[operation.operationId] = operation.copyWith(
      state: PandoraOfflineOperationState.failed,
      attemptCount: operation.attemptCount + 1,
      lastErrorCode: requireLocalIdentifier(errorCode, 'error code'),
    );
  }

  @override
  Future<void> markOperationApplied(String operationId) async {
    final operation = _active(operationId);
    _operations[operation.operationId] = operation.copyWith(
      state: PandoraOfflineOperationState.applied,
      clearError: true,
    );
  }

  @override
  Future<int> purgeExpired(DateTime now) async {
    final current = now.toUtc();
    final cacheIds = _cache.entries
        .where((entry) => !entry.value.expiresAt.isAfter(current))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in cacheIds) {
      _cache.remove(id);
    }
    final cutoff = current.subtract(PandoraLocalDataPolicy.maxRetention);
    final operationIds = _operations.entries
        .where((entry) {
          final operation = entry.value;
          return (operation.state == PandoraOfflineOperationState.applied ||
                  operation.state == PandoraOfflineOperationState.failed) &&
              !operation.createdAt.isAfter(cutoff);
        })
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in operationIds) {
      final removed = _operations.remove(id);
      if (removed != null) _idempotency.remove(removed.idempotencyKey);
    }
    return cacheIds.length + operationIds.length;
  }

  @override
  Future<void> close() async {
    _cache.clear();
    _operations.clear();
    _idempotency.clear();
  }
}
