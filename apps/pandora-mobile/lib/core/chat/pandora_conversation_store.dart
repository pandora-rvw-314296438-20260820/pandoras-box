import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../local/pandora_local_data_policy.dart';
import '../local/pandora_local_store_contract.dart';
import 'pandora_chat_state.dart';

/// An identity-bearing, bounded local projection, never permission to execute.
/// Server history/readback remains authoritative for accepted work.
class PandoraConversationSnapshot {
  PandoraConversationSnapshot({
    required this.state,
    required this.capturedAt,
    this.truncated = false,
    Set<String> requiresRequestReviewTurnIds = const {},
  }) : requiresRequestReviewTurnIds =
            Set<String>.unmodifiable(requiresRequestReviewTurnIds);

  final PandoraChatSessionState state;
  final DateTime capturedAt;
  final bool truncated;
  final Set<String> requiresRequestReviewTurnIds;

  bool get requiresReconciliation => state.hasUnresolvedOutcome;
}

/// Persists the active conversation and explicit thread history in the existing
/// encrypted store. Every key is account/context scoped even when the supplied
/// backend is shared by multiple account scopes.
///
/// Keep one instance for a retained conversation controller. Instances sharing
/// the same backend and scope also share a serial write lane. Reset fences are
/// installed synchronously, before any pending I/O can resume, and stale writes
/// cannot recreate the active pointer after New Chat.
class PandoraConversationStore {
  PandoraConversationStore(
    this._store, {
    required this.scopeId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (scopeId.trim().isEmpty || scopeId.length > 1024) {
      throw const FormatException('Conversation scope must be bounded.');
    }
    final scopes = _lanes[_store] ??= <String, _ConversationWriteLane>{};
    _lane = scopes.putIfAbsent(scopeId, _ConversationWriteLane.new);
  }

  static const int schemaVersion = 1;
  static const int maxCachedRequestBytes = 32768;
  static const Duration retention = Duration(days: 7);
  static final Expando<Map<String, _ConversationWriteLane>> _lanes =
      Expando<Map<String, _ConversationWriteLane>>();

  final PandoraLocalStore _store;
  final String scopeId;
  final DateTime Function() _clock;
  late final _ConversationWriteLane _lane;

  /// Initialize a newly mounted controller above this backend/scope's latest
  /// fence, including when New Chat or expiry left no active snapshot to restore.
  int get nextScopeEpoch => _lane.scopeEpoch + 1;

  String get _activeKey => 'conversation_active_${_digest(scopeId)}';
  String _threadKey(String threadId) =>
      'conversation_thread_${_digest(jsonEncode([scopeId, threadId]))}';

  /// Returns false for superseded writes or an uncacheable current snapshot.
  /// Requests are frozen before this call; caching never mutates the live state.
  /// A rejected payload invalidates the active pointer rather than presenting a
  /// stale draft or conversation as the latest state after restart.
  Future<bool> save(PandoraChatSessionState state) {
    _validateState(state, scopeId);
    if (state.scopeEpoch < _lane.scopeEpoch) return Future.value(false);
    final retired = '${state.scopeEpoch}:${state.conversationId}';
    if (_lane.retiredConversations.contains(retired)) {
      return Future.value(false);
    }
    if (state.scopeEpoch == _lane.scopeEpoch &&
        _lane.conversationId != null &&
        state.conversationId != _lane.conversationId) {
      return Future.value(false);
    }
    if (state.scopeEpoch == _lane.scopeEpoch &&
        state.conversationId == _lane.conversationId &&
        state.revision <= _lane.revision) {
      return Future.value(false);
    }
    if (state.scopeEpoch > _lane.scopeEpoch) {
      _lane.retiredConversations.clear();
    }
    _lane
      ..scopeEpoch = state.scopeEpoch
      ..conversationId = state.conversationId
      ..revision = state.revision;
    final intent = ++_lane.intent;
    final capturedAt = _clock().toUtc();
    final payload = _boundedPayload(state, capturedAt);
    return _serial(() async {
      if (intent != _lane.intent) return false;
      if (payload == null) {
        await _store.deleteCache(
          PandoraLocalNamespace.recentConversation,
          _activeKey,
        );
        return false;
      }
      final expiresAt = _clock().toUtc().add(retention);
      final sourceRevision =
          '${state.scopeEpoch}:${state.conversationId}:${state.revision}';
      if (state.threadId != null) {
        await _store.putCache(
          namespace: PandoraLocalNamespace.recentConversation,
          key: _threadKey(state.threadId!),
          payload: payload,
          expiresAt: expiresAt,
          sourceRevision: sourceRevision,
        );
        if (intent != _lane.intent) return false;
      }
      // The active pointer and snapshot share one atomic cache record. An
      // interruption cannot leave a pointer referring to another revision.
      await _store.putCache(
        namespace: PandoraLocalNamespace.recentConversation,
        key: _activeKey,
        payload: payload,
        expiresAt: expiresAt,
        sourceRevision: sourceRevision,
      );
      return intent == _lane.intent;
    });
  }

  Future<PandoraConversationSnapshot?> loadActive() => _read(_activeKey);

  Future<PandoraConversationSnapshot?> loadThread(String threadId) {
    final identity = requireLocalIdentifier(threadId, 'thread id');
    return _read(_threadKey(identity), expectedThreadId: identity);
  }

  /// Pass the controller's new epoch after reset/navigation invalidation. Only
  /// the active pointer is removed; explicit canonical thread history survives.
  Future<void> resetActive({required int scopeEpoch}) {
    if (scopeEpoch < 0 || scopeEpoch < _lane.scopeEpoch) {
      return Future.error(
        ArgumentError('Reset must use the current or a newer scope epoch.'),
      );
    }
    if (_lane.conversationId != null) {
      _lane.retiredConversations.add(
        '${_lane.scopeEpoch}:${_lane.conversationId}',
      );
    }
    _lane
      ..scopeEpoch = scopeEpoch
      ..conversationId = null
      ..revision = -1;
    _lane.intent++;
    return _serial(() => _store.deleteCache(
          PandoraLocalNamespace.recentConversation,
          _activeKey,
        ));
  }

  Future<void> flush() => _lane.tail;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _lane.tail.then((_) => operation());
    // One failed disk write must not poison every subsequent save/reset.
    _lane.tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<PandoraConversationSnapshot?> _read(
    String key, {
    String? expectedThreadId,
  }) {
    final intent = _lane.intent;
    return _serial(() async {
      if (intent != _lane.intent) return null;
      final record = await _store.getCache(
        PandoraLocalNamespace.recentConversation,
        key,
      );
      if (record == null || intent != _lane.intent) return null;
      if (!record.expiresAt.toUtc().isAfter(_clock().toUtc())) {
        await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
        return null;
      }
      try {
        if (utf8.encode(record.payloadJson).length >
            PandoraLocalDataPolicy.maxPayloadBytes) {
          throw const FormatException('Conversation snapshot is too large.');
        }
        final payload = _map(jsonDecode(record.payloadJson));
        PandoraLocalDataPolicy.encodePayload(payload);
        final snapshot = _decode(payload, scopeId);
        if (expectedThreadId != null &&
            snapshot.state.threadId != expectedThreadId) {
          throw const FormatException('Conversation thread does not match.');
        }
        return snapshot;
      } on FormatException {
        await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
        return null;
      } on TypeError {
        await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
        return null;
      } on ArgumentError {
        await _store.deleteCache(PandoraLocalNamespace.recentConversation, key);
        return null;
      }
    });
  }
}

class _ConversationWriteLane {
  Future<void> tail = Future<void>.value();
  int intent = 0;
  int scopeEpoch = -1;
  int revision = -1;
  String? conversationId;
  final Set<String> retiredConversations = <String>{};
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

Map<String, Object?>? _boundedPayload(
  PandoraChatSessionState state,
  DateTime capturedAt,
) {
  final history = state.history.map((value) => value.toJson()).toList();
  final turns = state.turns.map(_turnJson).toList();
  final payload = <String, Object?>{
    'schemaVersion': PandoraConversationStore.schemaVersion,
    'scopeId': state.scopeId,
    'scopeEpoch': state.scopeEpoch,
    'conversationId': state.conversationId,
    'threadId': state.threadId,
    'revision': state.revision,
    'draft': <String, Object?>{
      'text': state.draft.text,
      'revision': state.draft.revision,
    },
    'preferences': state.preferences.toJson(),
    'history': history,
    'turns': turns,
    'activeTurnId': state.activeTurnId,
    'queuedTurnId': state.queuedTurnId,
    'capturedAt': capturedAt.toIso8601String(),
    'truncated': false,
  };
  while (true) {
    try {
      PandoraLocalDataPolicy.encodePayload(payload);
      return payload;
    } on FormatException {
      // Drop only reconstructible historical content, never change a pending
      // request or silently clip the current draft. The bounded cache is not an
      // archive; canonical IDs still select the correct server history.
      if (history.isNotEmpty) {
        history.removeAt(0);
        payload['truncated'] = true;
        continue;
      }
      final index = turns.indexWhere((turn) =>
          turn['id'] != state.activeTurnId &&
          turn['id'] != state.queuedTurnId &&
          turn != turns.last &&
          const {'completed', 'cancelled', 'superseded'}
              .contains(turn['phase']));
      if (index >= 0) {
        turns.removeAt(index);
        payload['truncated'] = true;
        continue;
      }
      return null;
    }
  }
}

Map<String, Object?> _turnJson(PandoraChatTurn turn) {
  final encodedRequest =
      turn.requestAvailable ? _cacheableRequest(turn.request) : null;
  return <String, Object?>{
    'id': turn.id,
    'text': turn.text,
    'createdAt': turn.createdAt.toUtc().toIso8601String(),
    'sequence': turn.sequence,
    'phase': turn.phase.name,
    'preferences': turn.preferences.toJson(),
    'requestAvailable': encodedRequest != null,
    if (encodedRequest != null) 'request': turn.request,
    if (encodedRequest != null) 'requestDigest': _digest(encodedRequest),
    'attempts': turn.attempts.map(_attemptJson).toList(),
    'reply': turn.reply,
    'userMessageId': turn.userMessageId,
    'assistantMessageId': turn.assistantMessageId,
    'serverSequence': turn.serverSequence,
    'failure': _failureJson(turn.failure),
    'receipt': _receiptJson(turn.receipt),
  };
}

String? _cacheableRequest(Map<String, Object?> request) {
  // A path/blob URI is not durable attachment content. Keep the live request
  // intact in memory but require review after restart instead of sending a
  // stripped or substituted payload under the same logical identity.
  if (_hasEphemeralReference(request)) return null;
  try {
    final encoded = PandoraLocalDataPolicy.encodePayload(request);
    return utf8.encode(encoded).length <=
            PandoraConversationStore.maxCachedRequestBytes
        ? encoded
        : null;
  } on FormatException {
    return null;
  }
}

bool _hasEphemeralReference(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll('_', '');
      if (const {'filepath', 'localpath', 'temporarypath', 'temppath'}
              .contains(key) &&
          entry.value != null) {
        return true;
      }
      if (_hasEphemeralReference(entry.value)) return true;
    }
  } else if (value is List) {
    return value.any(_hasEphemeralReference);
  } else if (value is String) {
    return value.startsWith('file://') ||
        value.startsWith('content://') ||
        value.startsWith('blob:') ||
        value.startsWith('/storage/') ||
        value.startsWith('/data/user/');
  }
  return false;
}

Map<String, Object?> _attemptJson(PandoraChatAttempt attempt) =>
    <String, Object?>{
      // Identity fields are flattened; no credentials or transport tokens are
      // persisted, and the existing local secret-field policy stays unchanged.
      'scopeId': attempt.token.scopeId,
      'scopeEpoch': attempt.token.scopeEpoch,
      'conversationId': attempt.token.conversationId,
      'turnId': attempt.token.turnId,
      'attemptId': attempt.token.attemptId,
      'generation': attempt.token.generation,
      'deliveryEpoch': attempt.token.deliveryEpoch,
      'phase': attempt.phase.name,
      'startedAt': attempt.startedAt.toUtc().toIso8601String(),
      'lastSequence': attempt.lastSequence,
      'lastStreamSequence': attempt.lastStreamSequence,
      'activityJobId': attempt.activityJobId,
      'finishedAt': attempt.finishedAt?.toUtc().toIso8601String(),
      'failure': _failureJson(attempt.failure),
      'receipt': _receiptJson(attempt.receipt),
      'supersededByAttemptId': attempt.supersededByAttemptId,
      'cancellationRequested': attempt.cancellationRequested,
      'deliveryFailures': attempt.deliveryFailures
          .map((delivery) => <String, Object?>{
                'deliveryEpoch': delivery.deliveryEpoch,
                'observedAt': delivery.observedAt.toUtc().toIso8601String(),
                'failure': _failureJson(delivery.failure),
              })
          .toList(),
    };

Map<String, Object?>? _failureJson(PandoraChatFailure? failure) =>
    failure == null
        ? null
        : <String, Object?>{
            'message': failure.message,
            'code': failure.code,
            'recoverable': failure.recoverable,
            'outcomeUnknown': failure.outcomeUnknown,
          };

Map<String, Object?>? _receiptJson(PandoraChatExecutionReceipt? receipt) {
  if (receipt == null) return null;
  final executionStatus = _executionStatus(receipt.routing['executionStatus']);
  final conversationLane =
      _conversationLane(receipt.routing['conversationLane']);
  final needsClarification = receipt.routing['needsClarification'];
  return <String, Object?>{
    'provider': receipt.provider,
    'model': receipt.model,
    'providerRequestId': receipt.providerRequestId,
    'assistantMessageId': receipt.assistantMessageId,
    if (receipt.inspection != null) 'inspection': receipt.inspection,
    // Preserve factual execution outcome separately from a stopped display.
    if (executionStatus != null) 'executionStatus': executionStatus,
    if (conversationLane != null) 'conversationLane': conversationLane,
    if (needsClarification is bool) 'needsClarification': needsClarification,
    // Other routing/usage diagnostics remain in authoritative telemetry.
  };
}

String? _executionStatus(Object? value) => const {
      'pending',
      'accepted',
      'processing',
      'streaming',
      'completed',
      'cancelled',
      'cancelling',
      'failed',
      'failedRecoverably',
      'failedPermanently',
      'failed_recoverably',
      'failed_permanently',
      'reconciling',
      'superseded',
    }.contains(value)
        ? value as String
        : null;

String? _conversationLane(Object? value) =>
    value is String && RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)
        ? value
        : null;

PandoraConversationSnapshot _decode(
  Map<String, Object?> payload,
  String expectedScope,
) {
  if (payload['schemaVersion'] != PandoraConversationStore.schemaVersion ||
      payload['scopeId'] != expectedScope) {
    throw const FormatException('Conversation schema or scope does not match.');
  }
  final review = <String>{};
  final turns = <PandoraChatTurn>[];
  for (final value in _list(payload['turns'])) {
    final data = _map(value);
    final requestAvailable = _bool(data['requestAvailable']);
    final request =
        requestAvailable ? _map(data['request']) : const <String, Object?>{};
    if (requestAvailable) {
      final encoded = _cacheableRequest(request);
      if (encoded == null || _digest(encoded) != data['requestDigest']) {
        throw const FormatException('Cached request identity does not match.');
      }
    }
    var turn = PandoraChatTurn(
      id: _string(data['id']),
      text: _string(data['text']),
      createdAt: _date(data['createdAt']),
      sequence: _integer(data['sequence']),
      phase: _phase(data['phase']),
      preferences: PandoraChatPreferences.fromJson(_map(data['preferences'])),
      request: request,
      requestAvailable: requestAvailable,
      attempts:
          _list(data['attempts']).map((item) => _attempt(_map(item))).toList(),
      reply: _string(data['reply']),
      userMessageId: _optionalString(data['userMessageId']),
      assistantMessageId: _optionalString(data['assistantMessageId']),
      serverSequence: data['serverSequence'] == null
          ? null
          : _integer(data['serverSequence']),
      failure: _failure(data['failure']),
      receipt: _receipt(data['receipt']),
    );
    if (!requestAvailable &&
        turn.phase != PandoraChatPhase.completed &&
        turn.phase != PandoraChatPhase.superseded) {
      review.add(turn.id);
    }
    if (turn.phase == PandoraChatPhase.pending && turn.attempts.isEmpty) {
      turn = turn.copyWith(
        phase: requestAvailable
            ? PandoraChatPhase.failedRecoverably
            : PandoraChatPhase.failedPermanently,
        failure: PandoraChatFailure(
          message: requestAvailable
              ? 'This message was waiting to send. Review it before trying again.'
              : 'Review this message and reattach its files before sending it again.',
          code: 'UNSENT_AFTER_RESTART',
          recoverable: requestAvailable,
        ),
      );
    } else if (!turn.phase.isTerminal || turn.failure?.outcomeUnknown == true) {
      const interrupted = PandoraChatFailure(
        message: 'Checking whether this message finished.',
        code: 'OUTCOME_REQUIRES_READBACK',
        outcomeUnknown: true,
      );
      turn = turn.copyWith(
        phase: PandoraChatPhase.reconciling,
        failure: interrupted,
        attempts: turn.attempts
            .map((attempt) => attempt == turn.attempt
                ? attempt.copyWith(
                    phase: PandoraChatPhase.reconciling,
                    failure: interrupted,
                  )
                : attempt)
            .toList(),
      );
    } else if (!requestAvailable &&
        turn.phase == PandoraChatPhase.failedRecoverably) {
      final admissionUnresolved = turn.failure?.code == 'CHAT_NOT_ADMITTED';
      turn = turn.copyWith(
        phase: admissionUnresolved
            ? PandoraChatPhase.failedRecoverably
            : PandoraChatPhase.failedPermanently,
        failure: PandoraChatFailure(
          message:
              'Review this message and reattach its files before sending it again.',
          code: admissionUnresolved
              ? 'CHAT_NOT_ADMITTED'
              : 'CACHED_REQUEST_REQUIRES_REVIEW',
          recoverable: admissionUnresolved,
        ),
      );
    }
    turns.add(turn);
  }
  final draft = _map(payload['draft']);
  final priorActiveId = _optionalString(payload['activeTurnId']);
  final priorQueuedId = _optionalString(payload['queuedTurnId']);
  if ((priorActiveId != null &&
          !turns.any((turn) => turn.id == priorActiveId)) ||
      (priorQueuedId != null &&
          !turns.any((turn) => turn.id == priorQueuedId))) {
    throw const FormatException('Cached active turn is missing.');
  }
  final state = PandoraChatSessionState(
    scopeId: _string(payload['scopeId']),
    scopeEpoch: _integer(payload['scopeEpoch']),
    conversationId: _string(payload['conversationId']),
    threadId: _optionalString(payload['threadId']),
    revision: _integer(payload['revision']),
    draft: PandoraChatDraftState(
      text: _string(draft['text']),
      revision: _integer(draft['revision']),
    ),
    preferences: PandoraChatPreferences.fromJson(_map(payload['preferences'])),
    history: _list(payload['history'])
        .map((value) => PandoraChatHistoryMessage.fromJson(_map(value)))
        .toList(),
    turns: turns,
    activeTurnId: turns.any((turn) =>
            turn.id == priorActiveId &&
            turn.phase == PandoraChatPhase.reconciling)
        ? priorActiveId
        : null,
    // A cached queue is saved user intent, never an executable restart queue.
    queuedTurnId: null,
  );
  _validateState(state, expectedScope);
  return PandoraConversationSnapshot(
    state: state,
    capturedAt: _date(payload['capturedAt']),
    truncated: _bool(payload['truncated']),
    requiresRequestReviewTurnIds: review,
  );
}

PandoraChatAttempt _attempt(Map<String, Object?> data) => PandoraChatAttempt(
      token: PandoraChatAttemptToken(
        scopeId: _string(data['scopeId']),
        scopeEpoch: _integer(data['scopeEpoch']),
        conversationId: _string(data['conversationId']),
        turnId: _string(data['turnId']),
        attemptId: _string(data['attemptId']),
        generation: _integer(data['generation']),
        deliveryEpoch:
            data['deliveryEpoch'] == null ? 0 : _integer(data['deliveryEpoch']),
      ),
      phase: _phase(data['phase']),
      startedAt: _date(data['startedAt']),
      lastSequence: _integer(data['lastSequence']),
      lastStreamSequence: data['lastStreamSequence'] == null
          ? 0
          : _integer(data['lastStreamSequence']),
      activityJobId: _optionalString(data['activityJobId']),
      finishedAt: data['finishedAt'] == null ? null : _date(data['finishedAt']),
      failure: _failure(data['failure']),
      receipt: _receipt(data['receipt']),
      supersededByAttemptId: _optionalString(data['supersededByAttemptId']),
      cancellationRequested: _bool(data['cancellationRequested']),
      deliveryFailures:
          _list(data['deliveryFailures'] ?? const []).map((value) {
        final delivery = _map(value);
        final failure = _failure(delivery['failure']);
        if (failure == null) {
          throw const FormatException('Missing delivery failure evidence.');
        }
        return PandoraChatDeliveryFailure(
          deliveryEpoch: _integer(delivery['deliveryEpoch']),
          observedAt: _date(delivery['observedAt']),
          failure: failure,
        );
      }).toList(),
    );

PandoraChatFailure? _failure(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  return PandoraChatFailure(
    message: _string(data['message']),
    code: _optionalString(data['code']),
    recoverable: _bool(data['recoverable']),
    outcomeUnknown: _bool(data['outcomeUnknown']),
  );
}

PandoraChatExecutionReceipt? _receipt(Object? value) {
  if (value == null) return null;
  final data = _map(value);
  final executionStatus = _executionStatus(data['executionStatus']);
  final conversationLane = _conversationLane(data['conversationLane']);
  final needsClarification = data['needsClarification'];
  return PandoraChatExecutionReceipt(
    provider: _optionalString(data['provider']),
    model: _optionalString(data['model']),
    providerRequestId: _optionalString(data['providerRequestId']),
    assistantMessageId: _optionalString(data['assistantMessageId']),
    inspection: data['inspection'] is Map ? _map(data['inspection']) : null,
    routing: {
      if (executionStatus != null) 'executionStatus': executionStatus,
      if (conversationLane != null) 'conversationLane': conversationLane,
      if (needsClarification is bool) 'needsClarification': needsClarification,
    },
  );
}

void _validateState(PandoraChatSessionState state, String expectedScope) {
  if (state.scopeId != expectedScope ||
      state.scopeEpoch < 0 ||
      state.revision < 0 ||
      state.draft.revision < 0 ||
      !state.preferences.isValid) {
    throw const FormatException('Conversation scope or revision is invalid.');
  }
  requireLocalIdentifier(state.conversationId, 'conversation id');
  if (state.threadId != null) {
    requireLocalIdentifier(state.threadId!, 'thread id');
  }
  final historyIds = <String>{};
  for (final message in state.history) {
    requireLocalIdentifier(message.id, 'message id');
    if (state.threadId == null ||
        message.threadId != state.threadId ||
        !const {'user', 'assistant', 'pandora'}.contains(message.role) ||
        !historyIds.add(message.id) ||
        (message.sequence != null && message.sequence! < 0)) {
      throw const FormatException('Conversation history identity is invalid.');
    }
  }
  final turnIds = <String>{};
  final attemptIds = <String>{};
  for (final turn in state.turns) {
    requireLocalIdentifier(turn.id, 'turn id');
    if (!turnIds.add(turn.id) ||
        turn.sequence < 0 ||
        !turn.preferences.isValid) {
      throw const FormatException('Conversation turn identity is invalid.');
    }
    if (state.threadId == null &&
        (turn.userMessageId != null ||
            turn.assistantMessageId != null ||
            turn.serverSequence != null)) {
      throw const FormatException('Server message identity requires a thread.');
    }
    if (turn.userMessageId != null) {
      requireLocalIdentifier(turn.userMessageId!, 'user message id');
    }
    if (turn.assistantMessageId != null) {
      requireLocalIdentifier(turn.assistantMessageId!, 'assistant message id');
    }
    for (final attempt in turn.attempts) {
      requireLocalIdentifier(attempt.token.attemptId, 'attempt id');
      if (!attemptIds.add(attempt.token.attemptId) ||
          attempt.token.scopeId != state.scopeId ||
          attempt.token.scopeEpoch != state.scopeEpoch ||
          attempt.token.conversationId != state.conversationId ||
          attempt.token.turnId != turn.id ||
          attempt.token.generation < 0 ||
          attempt.token.deliveryEpoch < 0 ||
          attempt.lastSequence < 0 ||
          attempt.lastStreamSequence < 0) {
        throw const FormatException(
            'Conversation attempt identity is invalid.');
      }
      var priorDeliveryEpoch = -1;
      for (final delivery in attempt.deliveryFailures) {
        if (delivery.deliveryEpoch <= priorDeliveryEpoch ||
            delivery.deliveryEpoch >= attempt.token.deliveryEpoch) {
          throw const FormatException('Delivery failure identity is invalid.');
        }
        priorDeliveryEpoch = delivery.deliveryEpoch;
      }
    }
  }
  if ((state.activeTurnId != null && !turnIds.contains(state.activeTurnId)) ||
      (state.queuedTurnId != null && !turnIds.contains(state.queuedTurnId))) {
    throw const FormatException(
        'Conversation active turn identity is invalid.');
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a conversation object.');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value) {
  if (value is! List) {
    throw const FormatException('Expected a conversation list.');
  }
  return List<Object?>.from(value);
}

String _string(Object? value) {
  if (value is! String) {
    throw const FormatException('Expected conversation text.');
  }
  return value;
}

String? _optionalString(Object? value) => value == null ? null : _string(value);

int _integer(Object? value) {
  if (value is! int) {
    throw const FormatException('Expected a conversation revision.');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('Expected a conversation flag.');
  }
  return value;
}

DateTime _date(Object? value) => DateTime.parse(_string(value)).toUtc();
PandoraChatPhase _phase(Object? value) =>
    PandoraChatPhase.values.byName(_string(value));
