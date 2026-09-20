import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'pandora_local_data_policy.dart';
import 'pandora_local_store_contract.dart';

class PandoraLocalStateCache {
  PandoraLocalStateCache(
    this._store, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PandoraLocalStore _store;
  final DateTime Function() _clock;

  Future<void> cachePermissionState({
    required String capability,
    required Map<String, Object?> state,
  }) async {
    final key = 'permission_${_digest(capability)}';
    final now = _clock().toUtc();
    await _store.putCache(
      namespace: PandoraLocalNamespace.permissionState,
      key: key,
      payload: <String, Object?>{
        'capability': capability,
        'state': state,
        'capturedAt': now.toIso8601String(),
      },
      expiresAt: now.add(const Duration(minutes: 15)),
    );
  }

  Future<void> cacheSelectedContact({
    required String displayName,
    required String phoneNumber,
  }) async {
    final number = phoneNumber.trim();
    if (number.isEmpty) return;
    final now = _clock().toUtc();
    await _store.putCache(
      namespace: PandoraLocalNamespace.contactMetadata,
      key: 'contact_${_digest(number)}',
      payload: <String, Object?>{
        'displayName': displayName.trim(),
        'phoneNumber': number,
        'capturedAt': now.toIso8601String(),
      },
      expiresAt: now.add(PandoraLocalDataPolicy.contactRetention),
    );
  }

  Future<void> cacheLocalReminder({
    required String operationId,
    required String title,
    required DateTime triggerAt,
    required String state,
  }) async {
    final now = _clock().toUtc();
    final retentionEnd = now.add(PandoraLocalDataPolicy.maxRetention);
    final desiredEnd = triggerAt.toUtc().add(const Duration(days: 1));
    final expiresAt =
        desiredEnd.isBefore(retentionEnd) ? desiredEnd : retentionEnd;
    if (!expiresAt.isAfter(now)) return;
    await _store.putCache(
      namespace: PandoraLocalNamespace.offlineReminder,
      key: requireLocalIdentifier(operationId, 'operation id'),
      payload: <String, Object?>{
        'title': title.trim(),
        'triggerAt': triggerAt.toUtc().toIso8601String(),
        'state': state,
        'capturedAt': now.toIso8601String(),
      },
      expiresAt: expiresAt,
    );
  }

  Future<void> cacheRecentConversation({
    required String threadIdentity,
    required List<Map<String, Object?>> messages,
  }) async {
    if (messages.isEmpty) return;
    final now = _clock().toUtc();
    final bounded = messages.length <= 30
        ? messages
        : messages.sublist(messages.length - 30);
    final payload = <String, Object?>{
      'messages': bounded,
      'capturedAt': now.toIso8601String(),
    };
    final expiresAt = now.add(const Duration(days: 7));
    await _store.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: 'thread_${_digest(threadIdentity)}',
      payload: payload,
      expiresAt: expiresAt,
    );
    if (threadIdentity.trim() != 'local-chat') {
      await _store.putCache(
        namespace: PandoraLocalNamespace.recentConversation,
        key: 'thread_${_digest('local-chat')}',
        payload: payload,
        expiresAt: expiresAt,
      );
    }
  }

  Future<List<Map<String, Object?>>> loadRecentConversation({
    required String threadIdentity,
  }) async {
    final key = 'thread_${_digest(threadIdentity)}';
    final record = await _store.getCache(
      PandoraLocalNamespace.recentConversation,
      key,
    );
    if (record == null) return const <Map<String, Object?>>[];
    final now = _clock().toUtc();
    if (!record.expiresAt.toUtc().isAfter(now)) {
      await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
      return const <Map<String, Object?>>[];
    }
    try {
      final decoded = jsonDecode(record.payloadJson);
      if (decoded is! Map || decoded['messages'] is! List) {
        return const <Map<String, Object?>>[];
      }
      final output = <Map<String, Object?>>[];
      for (final value in decoded['messages'] as List) {
        if (value is! Map) continue;
        output.add(
          value.map((key, item) => MapEntry(key.toString(), item)),
        );
      }
      return output;
    } on FormatException {
      await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> cacheMemoryContext({
    required String contextId,
    required Object? boundedContext,
    String? sourceRevision,
  }) async {
    final now = _clock().toUtc();
    await _store.putCache(
      namespace: PandoraLocalNamespace.memoryContext,
      key: 'memory_${_digest(contextId)}',
      payload: boundedContext,
      expiresAt: now.add(PandoraLocalDataPolicy.memoryRetention),
      sourceRevision: sourceRevision,
    );
  }

  Future<Object?> loadMemoryContext({
    required String contextId,
  }) async {
    final key = 'memory_${_digest(contextId)}';
    final record = await _store.getCache(
      PandoraLocalNamespace.memoryContext,
      key,
    );
    if (record == null) return null;
    final now = _clock().toUtc();
    if (!record.expiresAt.toUtc().isAfter(now)) {
      await _store.deleteCache(PandoraLocalNamespace.memoryContext, key);
      return null;
    }
    try {
      return jsonDecode(record.payloadJson);
    } on FormatException {
      await _store.deleteCache(PandoraLocalNamespace.memoryContext, key);
      return null;
    }
  }

  String _digest(String value) =>
      sha256.convert(utf8.encode(value.trim())).toString().substring(0, 32);
}
