import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'pandora_local_data_policy.dart';
import 'pandora_local_store_contract.dart';
import 'pandora_local_store_stub.dart';

const _databaseName = 'pandora_local_v1.db';
const _databaseVersion = 1;
const _storageKey = 'sqlcipher_key_v1';

final _secureStorage = FlutterSecureStorage(
  aOptions: const AndroidOptions(
    storageNamespace: 'pandora_local_database_v1',
  ),
);

Future<String> _loadOrCreateDatabasePassword() async {
  final existing = await _secureStorage.read(key: _storageKey);
  if (existing != null && existing.length >= 32) return existing;

  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  final password = base64UrlEncode(bytes);
  await _secureStorage.write(key: _storageKey, value: password);
  return password;
}

Future<PandoraLocalStore> openPandoraLocalStore() async {
  try {
    final password = await _loadOrCreateDatabasePassword();
    final root = await getDatabasesPath();
    final database = await openDatabase(
      p.join(root, _databaseName),
      password: password,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache_records (
            namespace TEXT NOT NULL,
            record_key TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            expires_at_ms INTEGER NOT NULL,
            source_revision TEXT,
            PRIMARY KEY (namespace, record_key)
          )
        ''');
        await db.execute(
          'CREATE INDEX cache_records_expiry_idx ON cache_records(expires_at_ms)',
        );
        await db.execute('''
          CREATE TABLE sync_queue (
            operation_id TEXT PRIMARY KEY,
            idempotency_key TEXT NOT NULL UNIQUE,
            capability TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            next_attempt_at_ms INTEGER NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
            state TEXT NOT NULL CHECK (state IN ('pending','retry','failed','applied')),
            last_error_code TEXT
          )
        ''');
        await db.execute('''
          CREATE INDEX sync_queue_ready_idx
          ON sync_queue(state, next_attempt_at_ms, created_at_ms)
        ''');
      },
    );
    return SqlCipherPandoraLocalStore(database);
  } catch (_) {
    // Never fall back to plaintext persistence. If encrypted storage cannot
    // initialize, keep local state memory-only for this process.
    return MemoryPandoraLocalStore();
  }
}

class SqlCipherPandoraLocalStore implements PandoraLocalStore {
  SqlCipherPandoraLocalStore(this._database, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Database _database;
  final DateTime Function() _clock;

  @override
  Future<void> putCache({
    required PandoraLocalNamespace namespace,
    required String key,
    required Object? payload,
    required DateTime expiresAt,
    String? sourceRevision,
  }) async {
    final recordKey = requireLocalIdentifier(key, 'cache key');
    final now = _clock().toUtc();
    PandoraLocalDataPolicy.validateExpiry(
      namespace: namespace,
      now: now,
      expiresAt: expiresAt,
    );
    final encoded = PandoraLocalDataPolicy.encodePayload(payload);
    await _database.insert(
      'cache_records',
      <String, Object?>{
        'namespace': namespace.name,
        'record_key': recordKey,
        'payload_json': encoded,
        'updated_at_ms': now.millisecondsSinceEpoch,
        'expires_at_ms': expiresAt.toUtc().millisecondsSinceEpoch,
        'source_revision': sourceRevision,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<PandoraLocalCacheRecord?> getCache(
    PandoraLocalNamespace namespace,
    String key,
  ) async {
    final recordKey = requireLocalIdentifier(key, 'cache key');
    final rows = await _database.query(
      'cache_records',
      where: 'namespace = ? AND record_key = ?',
      whereArgs: <Object?>[namespace.name, recordKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      row['expires_at_ms']! as int,
      isUtc: true,
    );
    if (!expiresAt.isAfter(_clock().toUtc())) {
      await deleteCache(namespace, recordKey);
      return null;
    }
    return PandoraLocalCacheRecord(
      namespace: namespace,
      key: recordKey,
      payloadJson: row['payload_json']! as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at_ms']! as int,
        isUtc: true,
      ),
      expiresAt: expiresAt,
      sourceRevision: row['source_revision'] as String?,
    );
  }

  @override
  Future<void> deleteCache(PandoraLocalNamespace namespace, String key) async {
    await _database.delete(
      'cache_records',
      where: 'namespace = ? AND record_key = ?',
      whereArgs: <Object?>[
        namespace.name,
        requireLocalIdentifier(key, 'cache key'),
      ],
    );
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
    final idempotency =
        requireLocalIdentifier(idempotencyKey, 'idempotency key');
    final boundedCapability = requireLocalIdentifier(capability, 'capability');
    final encoded = PandoraLocalDataPolicy.encodePayload(payload);
    final created = createdAt.toUtc();

    await _database.transaction((txn) async {
      final existing = await txn.query(
        'sync_queue',
        where: 'idempotency_key = ?',
        whereArgs: <Object?>[idempotency],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        final exactReplay = row['operation_id'] == operation &&
            row['capability'] == boundedCapability &&
            row['payload_json'] == encoded;
        if (!exactReplay) {
          throw StateError(
            'Idempotency key already belongs to a different local operation.',
          );
        }
        return;
      }
      await txn.insert('sync_queue', <String, Object?>{
        'operation_id': operation,
        'idempotency_key': idempotency,
        'capability': boundedCapability,
        'payload_json': encoded,
        'created_at_ms': created.millisecondsSinceEpoch,
        'next_attempt_at_ms': created.millisecondsSinceEpoch,
        'attempt_count': 0,
        'state': PandoraOfflineOperationState.pending.name,
      });
    });
  }

  @override
  Future<List<PandoraOfflineOperation>> pendingOperations({
    required DateTime now,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final rows = await _database.query(
      'sync_queue',
      where: "state IN ('pending','retry') AND next_attempt_at_ms <= ?",
      whereArgs: <Object?>[now.toUtc().millisecondsSinceEpoch],
      orderBy: 'created_at_ms ASC, operation_id ASC',
      limit: limit,
    );
    return rows.map(_operationFromRow).toList(growable: false);
  }

  PandoraOfflineOperation _operationFromRow(Map<String, Object?> row) {
    final stateName = row['state']! as String;
    final state = PandoraOfflineOperationState.values.firstWhere(
      (candidate) => candidate.name == stateName,
    );
    return PandoraOfflineOperation(
      operationId: row['operation_id']! as String,
      idempotencyKey: row['idempotency_key']! as String,
      capability: row['capability']! as String,
      payloadJson: row['payload_json']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_ms']! as int,
        isUtc: true,
      ),
      nextAttemptAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_attempt_at_ms']! as int,
        isUtc: true,
      ),
      attemptCount: row['attempt_count']! as int,
      state: state,
      lastErrorCode: row['last_error_code'] as String?,
    );
  }

  @override
  Future<void> markOperationRetry({
    required String operationId,
    required DateTime nextAttemptAt,
    required String errorCode,
  }) async {
    final updated = await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET state = ?, next_attempt_at_ms = ?, attempt_count = attempt_count + 1,
          last_error_code = ?
      WHERE operation_id = ? AND state IN ('pending','retry')
      ''',
      <Object?>[
        PandoraOfflineOperationState.retry.name,
        nextAttemptAt.toUtc().millisecondsSinceEpoch,
        requireLocalIdentifier(errorCode, 'error code'),
        requireLocalIdentifier(operationId, 'operation id'),
      ],
    );
    if (updated != 1) throw StateError('Local operation is not retryable.');
  }

  @override
  Future<void> markOperationFailed({
    required String operationId,
    required String errorCode,
  }) async {
    final updated = await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET state = ?, attempt_count = attempt_count + 1, last_error_code = ?
      WHERE operation_id = ? AND state IN ('pending','retry')
      ''',
      <Object?>[
        PandoraOfflineOperationState.failed.name,
        requireLocalIdentifier(errorCode, 'error code'),
        requireLocalIdentifier(operationId, 'operation id'),
      ],
    );
    if (updated != 1) throw StateError('Local operation is not fail-able.');
  }

  @override
  Future<void> markOperationApplied(String operationId) async {
    final updated = await _database.rawUpdate(
      '''
      UPDATE sync_queue
      SET state = ?, last_error_code = NULL
      WHERE operation_id = ? AND state IN ('pending','retry')
      ''',
      <Object?>[
        PandoraOfflineOperationState.applied.name,
        requireLocalIdentifier(operationId, 'operation id'),
      ],
    );
    if (updated != 1) throw StateError('Local operation is not applicable.');
  }

  @override
  Future<int> purgeExpired(DateTime now) async {
    final cutoff = now.toUtc();
    final cacheDeleted = await _database.delete(
      'cache_records',
      where: 'expires_at_ms <= ?',
      whereArgs: <Object?>[cutoff.millisecondsSinceEpoch],
    );
    final operationCutoff = cutoff
        .subtract(PandoraLocalDataPolicy.maxRetention)
        .millisecondsSinceEpoch;
    final operationsDeleted = await _database.delete(
      'sync_queue',
      where: "state IN ('applied','failed') AND created_at_ms <= ?",
      whereArgs: <Object?>[operationCutoff],
    );
    return cacheDeleted + operationsDeleted;
  }

  @override
  Future<void> close() => _database.close();
}
