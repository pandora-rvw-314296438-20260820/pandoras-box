import 'pandora_local_data_policy.dart';

enum PandoraOfflineOperationState { pending, retry, failed, applied }

class PandoraLocalCacheRecord {
  const PandoraLocalCacheRecord({
    required this.namespace,
    required this.key,
    required this.payloadJson,
    required this.updatedAt,
    required this.expiresAt,
    this.sourceRevision,
  });

  final PandoraLocalNamespace namespace;
  final String key;
  final String payloadJson;
  final DateTime updatedAt;
  final DateTime expiresAt;
  final String? sourceRevision;
}

class PandoraOfflineOperation {
  const PandoraOfflineOperation({
    required this.operationId,
    required this.idempotencyKey,
    required this.capability,
    required this.payloadJson,
    required this.createdAt,
    required this.nextAttemptAt,
    this.attemptCount = 0,
    this.state = PandoraOfflineOperationState.pending,
    this.lastErrorCode,
  });
  final String operationId;
  final String idempotencyKey;
  final String capability;
  final String payloadJson;
  final DateTime createdAt;
  final DateTime nextAttemptAt;
  final int attemptCount;
  final PandoraOfflineOperationState state;
  final String? lastErrorCode;

  PandoraOfflineOperation copyWith({
    DateTime? nextAttemptAt,
    int? attemptCount,
    PandoraOfflineOperationState? state,
    String? lastErrorCode,
    bool clearError = false,
  }) {
    return PandoraOfflineOperation(
      operationId: operationId,
      idempotencyKey: idempotencyKey,
      capability: capability,
      payloadJson: payloadJson,
      createdAt: createdAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      attemptCount: attemptCount ?? this.attemptCount,
      state: state ?? this.state,
      lastErrorCode: clearError ? null : lastErrorCode ?? this.lastErrorCode,
    );
  }
}

abstract interface class PandoraLocalStore {
  Future<void> putCache({
    required PandoraLocalNamespace namespace,
    required String key,
    required Object? payload,
    required DateTime expiresAt,
    String? sourceRevision,
  });

  Future<PandoraLocalCacheRecord?> getCache(
    PandoraLocalNamespace namespace,
    String key,
  );

  Future<void> deleteCache(PandoraLocalNamespace namespace, String key);

  Future<void> enqueue({
    required String operationId,
    required String idempotencyKey,
    required String capability,
    required Object? payload,
    required DateTime createdAt,
  });

  Future<List<PandoraOfflineOperation>> pendingOperations({
    required DateTime now,
    int limit = 50,
  });
  Future<void> markOperationRetry({
    required String operationId,
    required DateTime nextAttemptAt,
    required String errorCode,
  });

  Future<void> markOperationFailed({
    required String operationId,
    required String errorCode,
  });

  Future<void> markOperationApplied(String operationId);

  Future<int> purgeExpired(DateTime now);

  Future<void> close();
}

String requireLocalIdentifier(String value, String label) {
  final trimmed = value.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,191}$').hasMatch(trimmed)) {
    throw FormatException('$label must be a bounded identifier.');
  }
  return trimmed;
}
