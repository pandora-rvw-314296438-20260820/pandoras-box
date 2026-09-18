import 'dart:math' as math;

import 'pandora_local_store_contract.dart';

enum PandoraLocalSyncOutcome {
  applied,
  duplicate,
  retryableFailure,
  terminalFailure,
}

class PandoraLocalSyncResult {
  const PandoraLocalSyncResult({required this.outcome, this.errorCode});

  final PandoraLocalSyncOutcome outcome;
  final String? errorCode;
}

abstract interface class PandoraLocalSyncTransport {
  Future<PandoraLocalSyncResult> apply(PandoraOfflineOperation operation);
}

class PandoraLocalSyncReceipt {
  const PandoraLocalSyncReceipt({
    required this.attempted,
    required this.applied,
    required this.duplicates,
    required this.retried,
    required this.failed,
  });

  final int attempted;
  final int applied;
  final int duplicates;
  final int retried;
  final int failed;

  static const empty = PandoraLocalSyncReceipt(
    attempted: 0,
    applied: 0,
    duplicates: 0,
    retried: 0,
    failed: 0,
  );
}

class PandoraLocalSyncCoordinator {
  PandoraLocalSyncCoordinator({
    required PandoraLocalStore store,
    required PandoraLocalSyncTransport transport,
    DateTime Function()? clock,
    this.maxAttempts = 5,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 2),
  })  : _store = store,
        _transport = transport,
        _clock = clock ?? DateTime.now;

  final PandoraLocalStore _store;
  final PandoraLocalSyncTransport _transport;
  final DateTime Function() _clock;
  final int maxAttempts;
  final Duration baseBackoff;
  final Duration maxBackoff;
  bool _draining = false;

  Future<PandoraLocalSyncReceipt> drain({int limit = 25}) async {
    if (_draining) return PandoraLocalSyncReceipt.empty;
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    if (maxAttempts < 1 || maxAttempts > 20) {
      throw RangeError.range(maxAttempts, 1, 20, 'maxAttempts');
    }
    _draining = true;
    var applied = 0;
    var duplicates = 0;
    var retried = 0;
    var failed = 0;
    try {
      final now = _clock().toUtc();
      await _store.purgeExpired(now);
      final operations = await _store.pendingOperations(now: now, limit: limit);
      for (final operation in operations) {
        PandoraLocalSyncResult result;
        try {
          result = await _transport.apply(operation);
        } catch (_) {
          result = const PandoraLocalSyncResult(
            outcome: PandoraLocalSyncOutcome.retryableFailure,
            errorCode: 'transport_unavailable',
          );
        }
        switch (result.outcome) {
          case PandoraLocalSyncOutcome.applied:
            await _store.markOperationApplied(operation.operationId);
            applied += 1;
            break;
          case PandoraLocalSyncOutcome.duplicate:
            await _store.markOperationApplied(operation.operationId);
            duplicates += 1;
            break;
          case PandoraLocalSyncOutcome.retryableFailure:
            final nextAttempt = operation.attemptCount + 1;
            final errorCode = _boundedErrorCode(result.errorCode);
            if (nextAttempt >= maxAttempts) {
              await _store.markOperationFailed(
                operationId: operation.operationId,
                errorCode: 'retry_exhausted_$errorCode',
              );
              failed += 1;
              continue;
            }
            await _store.markOperationRetry(
              operationId: operation.operationId,
              nextAttemptAt: now.add(_backoffFor(operation.attemptCount)),
              errorCode: errorCode,
            );
            retried += 1;
            break;
          case PandoraLocalSyncOutcome.terminalFailure:
            await _store.markOperationFailed(
              operationId: operation.operationId,
              errorCode: _boundedErrorCode(result.errorCode),
            );
            failed += 1;
            break;
        }
      }
      return PandoraLocalSyncReceipt(
        attempted: operations.length,
        applied: applied,
        duplicates: duplicates,
        retried: retried,
        failed: failed,
      );
    } finally {
      _draining = false;
    }
  }

  Duration _backoffFor(int priorAttempts) {
    final exponent = math.min(priorAttempts, 12);
    final multiplier = 1 << exponent;
    final milliseconds = baseBackoff.inMilliseconds * multiplier;
    return Duration(
      milliseconds: math.min(milliseconds, maxBackoff.inMilliseconds),
    );
  }

  String _boundedErrorCode(String? value) {
    final normalized = (value ?? 'sync_failed')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._:-]'), '_');
    if (normalized.isEmpty) return 'sync_failed';
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }
}
