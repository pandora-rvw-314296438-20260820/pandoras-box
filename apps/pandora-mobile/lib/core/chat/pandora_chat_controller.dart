import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'pandora_chat_state.dart';

/// Owns local intent and projects verified execution events. It deliberately
/// performs no network requests: Activity remains the execution authority.
class PandoraChatController extends ChangeNotifier {
  PandoraChatController({
    required String scopeId,
    int initialScopeEpoch = 0,
    String Function()? newId,
    DateTime Function()? clock,
  })  : _newId = newId ?? _uuid,
        _clock = clock ?? DateTime.now {
    if (scopeId.trim().isEmpty) throw ArgumentError.value(scopeId, 'scopeId');
    if (initialScopeEpoch < 0) {
      throw ArgumentError.value(initialScopeEpoch, 'initialScopeEpoch');
    }
    _state = PandoraChatSessionState(
      scopeId: scopeId,
      scopeEpoch: initialScopeEpoch,
      conversationId: _newId(),
    );
  }

  final String Function() _newId;
  final DateTime Function() _clock;
  late PandoraChatSessionState _state;
  bool _disposed = false;
  PandoraChatSessionState get state => _state;

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final text = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }

  void _emit(PandoraChatSessionState value) {
    if (_disposed) return;
    _state = value.copyWith(revision: _state.revision + 1);
    notifyListeners();
  }

  bool setPreferences(PandoraChatPreferences value) {
    if (_disposed || !value.isValid) return false;
    _emit(_state.copyWith(preferences: value));
    return true;
  }

  void setDraft(String text) {
    if (_disposed || text == _state.draft.text) return;
    _emit(
      _state.copyWith(
        draft: PandoraChatDraftState(
          text: text,
          revision: _state.draft.revision + 1,
        ),
      ),
    );
  }

  PandoraChatDraftToken captureDraftToken() => PandoraChatDraftToken(
        scopeEpoch: _state.scopeEpoch,
        conversationId: _state.conversationId,
        revision: _state.draft.revision,
      );

  bool matchesDraft(PandoraChatDraftToken token) =>
      !_disposed &&
      token.scopeEpoch == _state.scopeEpoch &&
      token.conversationId == _state.conversationId &&
      token.revision == _state.draft.revision;

  bool applyDraftResult(
    PandoraChatDraftToken token,
    String text, {
    bool append = true,
  }) {
    if (!matchesDraft(token)) return false;
    final current = _state.draft.text;
    setDraft(append && current.trim().isNotEmpty ? '$current $text' : text);
    return true;
  }

  PandoraChatAdmission submitDraft({Map<String, Object?> payload = const {}}) =>
      submit(
        _state.draft.text,
        payload: payload,
        draftRevision: _state.draft.revision,
      );

  /// Admission and draft consumption are synchronous, before any adapter awaits.
  PandoraChatAdmission submit(
    String text, {
    Map<String, Object?> payload = const {},
    int? draftRevision,
  }) {
    if (_disposed) return const PandoraChatAdmission.rejected('disposed');
    if (draftRevision != null && draftRevision != _state.draft.revision) {
      return const PandoraChatAdmission.rejected('stale_draft');
    }
    final message = text.trim();
    if (message.isEmpty) return const PandoraChatAdmission.rejected('empty');
    if (!_state.historyReady) {
      return PandoraChatAdmission.rejected(
          _state.loadingHistory ? 'history_loading' : 'history_unverified');
    }
    if (_state.queuedTurnId != null) {
      return const PandoraChatAdmission.rejected('follow_up_already_pending');
    }
    final turn = PandoraChatTurn(
      id: _newId(),
      text: message,
      createdAt: _clock().toUtc(),
      sequence: max(
              _state.turns
                  .fold<int>(0, (highest, turn) => max(highest, turn.sequence)),
              _state.history.indexed.fold<int>(
                  0,
                  (highest, item) =>
                      max(highest, item.$2.sequence ?? item.$1 + 1))) +
          1,
      phase: PandoraChatPhase.pending,
      preferences: _state.preferences,
      request: {...payload, 'message': message},
    );
    final draft = _state.draft.text.trim() == message
        ? PandoraChatDraftState(revision: _state.draft.revision + 1)
        : _state.draft;
    if (_state.activeTurnId != null ||
        _state.hasUnresolvedOutcome ||
        _state.hasUnresolvedAdmission) {
      _emit(
        _state.copyWith(
          turns: [..._state.turns, turn],
          queuedTurnId: turn.id,
          draft: draft,
        ),
      );
      return PandoraChatAdmission.queued(turn.id);
    }
    return _dispatch(turn, append: true, draft: draft);
  }

  PandoraChatAdmission _dispatch(
    PandoraChatTurn turn, {
    bool append = false,
    bool retry = false,
    PandoraChatDraftState? draft,
  }) {
    final prior = turn.attempt;
    final token = PandoraChatAttemptToken(
      scopeId: _state.scopeId,
      scopeEpoch: _state.scopeEpoch,
      conversationId: _state.conversationId,
      turnId: turn.id,
      attemptId: _newId(),
      generation: (prior?.token.generation ?? 0) + 1,
    );
    final attempts = [...turn.attempts];
    if (prior != null) {
      attempts[attempts.length - 1] = prior.copyWith(
        supersededByAttemptId: token.attemptId,
      );
    }
    attempts.add(
      PandoraChatAttempt(
        token: token,
        phase: PandoraChatPhase.pending,
        startedAt: _clock().toUtc(),
      ),
    );
    // A queued turn snapshots preferences at dispatch. A retry must keep the
    // original admitted payload/preferences to satisfy its server fingerprint.
    final preferences = retry ? turn.preferences : _state.preferences;
    final clientHistory =
        retry ? const <Map<String, Object?>>[] : _completedClientHistory();
    final admitted = turn.copyWith(
      phase: PandoraChatPhase.pending,
      preferences: preferences,
      request: retry
          ? turn.request
          : <String, Object?>{
              ...turn.request,
              'message': turn.text,
              'modelSelection': preferences.modelSelectionJson,
              'mode': preferences.reasoningMode,
              if (clientHistory.isNotEmpty) 'clientHistory': clientHistory,
            },
      attempts: attempts,
      reply: '',
      failure: null,
      receipt: null,
    );
    _emit(
      _state.copyWith(
        turns: append ? [..._state.turns, admitted] : _replacing(admitted),
        activeTurnId: turn.id,
        queuedTurnId:
            _state.queuedTurnId == turn.id ? null : _state.queuedTurnId,
        draft: draft,
      ),
    );
    return PandoraChatAdmission.dispatched(
      PandoraChatDispatch(
        token: token,
        turn: admitted,
        threadId: _state.threadId,
        isRetry: retry,
        expectedGeneration: retry ? prior?.token.generation : null,
      ),
    );
  }

  PandoraChatAdmission takeQueued() {
    if (_disposed ||
        _state.activeTurnId != null ||
        _state.hasUnresolvedOutcome ||
        _state.hasUnresolvedAdmission ||
        !_state.historyReady) {
      return const PandoraChatAdmission.rejected('execution_unresolved');
    }
    final turn = _state.queuedTurn;
    if (turn == null) {
      return const PandoraChatAdmission.rejected('no_follow_up');
    }
    return _dispatch(turn);
  }

  PandoraChatAdmission retry(String turnId) {
    if (_disposed ||
        _state.activeTurnId != null ||
        _state.hasUnresolvedOutcome ||
        !_state.historyReady) {
      return const PandoraChatAdmission.rejected('execution_unresolved');
    }
    final turn = _state.turn(turnId);
    if (turn == null || !turn.canRetry) {
      return const PandoraChatAdmission.rejected('not_retryable');
    }
    if (turn.failure?.code == 'CHAT_NOT_ADMITTED') {
      return _redeliverUnadmitted(turn);
    }
    if (_state.queuedTurnId != null || _state.hasUnresolvedAdmission) {
      return const PandoraChatAdmission.rejected('execution_unresolved');
    }
    return _dispatch(turn, retry: turn.attempt != null);
  }

  /// Only the adapter's verified absence readback may authorize this transition.
  /// A lost retry acknowledgement may expose the prior failed server generation;
  /// the adapter must verify that exact predecessor before invoking this method.
  bool markNotAdmitted(PandoraChatAttemptToken token) {
    if (!isCurrent(token)) return false;
    final turn = _state.turn(token.turnId)!;
    final attempt = turn.attempt!;
    if (attempt.activityJobId != null ||
        attempt.lastSequence != 0 ||
        attempt.cancellationRequested) {
      return false;
    }
    const verifiedAbsence = PandoraChatFailure(
      message: 'Please try sending this message again.',
      code: 'CHAT_NOT_ADMITTED',
    );
    final updated = attempt.copyWith(
      phase: PandoraChatPhase.failedRecoverably,
      finishedAt: _clock().toUtc(),
      failure: attempt.failure ?? verifiedAbsence,
    );
    _emit(_state.copyWith(
      turns: _replacing(turn.copyWith(
        phase: PandoraChatPhase.failedRecoverably,
        failure: verifiedAbsence,
        attempts: [...turn.attempts.take(turn.attempts.length - 1), updated],
      )),
      activeTurnId: _state.activeTurnId == turn.id ? null : _state.activeTurnId,
    ));
    return true;
  }

  PandoraChatAdmission _redeliverUnadmitted(PandoraChatTurn turn) {
    final prior = turn.attempt;
    if (prior == null ||
        turn.failure?.code != 'CHAT_NOT_ADMITTED' ||
        prior.token.generation < 1 ||
        prior.activityJobId != null ||
        prior.lastSequence != 0 ||
        prior.cancellationRequested) {
      return const PandoraChatAdmission.rejected('not_retryable');
    }
    final token = PandoraChatAttemptToken(
      scopeId: _state.scopeId,
      scopeEpoch: _state.scopeEpoch,
      conversationId: _state.conversationId,
      turnId: turn.id,
      attemptId: prior.token.attemptId,
      generation: prior.token.generation,
      deliveryEpoch: prior.token.deliveryEpoch + 1,
    );
    final attempt = PandoraChatAttempt(
      token: token,
      phase: PandoraChatPhase.pending,
      startedAt: prior.startedAt,
      deliveryFailures: [
        ...prior.deliveryFailures,
        PandoraChatDeliveryFailure(
          deliveryEpoch: prior.token.deliveryEpoch,
          observedAt: prior.finishedAt ?? _clock().toUtc(),
          failure: prior.failure!,
        ),
      ],
    );
    final admitted = turn.copyWith(
      phase: PandoraChatPhase.pending,
      attempts: [...turn.attempts.take(turn.attempts.length - 1), attempt],
      reply: '',
      failure: null,
      receipt: null,
    );
    _emit(_state.copyWith(
      turns: _replacing(admitted),
      activeTurnId: turn.id,
    ));
    final isRetry = token.generation > 1;
    return PandoraChatAdmission.dispatched(PandoraChatDispatch(
      token: token,
      turn: admitted,
      threadId: _state.threadId,
      isRetry: isRetry,
      expectedGeneration: isRetry ? token.generation - 1 : null,
    ));
  }

  List<PandoraChatTurn> _replacing(PandoraChatTurn value) =>
      _state.turns.map((turn) => turn.id == value.id ? value : turn).toList();

  bool isCurrent(PandoraChatAttemptToken token) {
    if (_disposed ||
        token.scopeId != _state.scopeId ||
        token.scopeEpoch != _state.scopeEpoch ||
        token.conversationId != _state.conversationId) {
      return false;
    }
    final turn = _state.turn(token.turnId);
    return turn != null &&
        turn.attempt?.token == token &&
        !turn.phase.isTerminal &&
        turn.attempt?.supersededByAttemptId == null;
  }

  bool _admits(
    PandoraChatAttemptToken token,
    int? sequence, {
    bool content = false,
  }) {
    if (!isCurrent(token)) return false;
    final attempt = _state.turn(token.turnId)!.attempt!;
    if (content && attempt.cancellationRequested) return false;
    return sequence == null || sequence > attempt.lastSequence;
  }

  bool _validThread(String? threadId) =>
      threadId == null ||
      (threadId.trim().isNotEmpty &&
          (_state.threadId == null || threadId == _state.threadId));

  bool accept(
    PandoraChatAttemptToken token, {
    String? threadId,
    String? activityJobId,
    String? userMessageId,
    int? turnSequence,
    int? sequence,
  }) {
    if (!_admits(token, sequence) || !_validThread(threadId)) return false;
    final turn = _state.turn(token.turnId)!;
    final attempt = turn.attempt!;
    if (attempt.phase != PandoraChatPhase.pending) return false;
    final updated = attempt.copyWith(
      phase: PandoraChatPhase.accepted,
      lastSequence: sequence ?? attempt.lastSequence,
      activityJobId: activityJobId,
    );
    _emit(
      _state.copyWith(
        threadId: threadId ?? _state.threadId,
        turns: _replacing(
          turn.copyWith(
            phase: updated.phase,
            attempts: [
              ...turn.attempts.take(turn.attempts.length - 1),
              updated,
            ],
            userMessageId: userMessageId,
            serverSequence: turnSequence,
          ),
        ),
      ),
    );
    return true;
  }

  bool processing(PandoraChatAttemptToken token, {int? sequence}) => _update(
        token,
        phase: PandoraChatPhase.processing,
        sequence: sequence,
        content: true,
      );

  /// Route metadata is diagnostic provenance, never model-selection intent.
  bool recordExecutionReceipt(
    PandoraChatAttemptToken token,
    PandoraChatExecutionReceipt receipt,
  ) {
    if (!isCurrent(token)) return false;
    return _update(token,
        phase: _state.turn(token.turnId)!.phase, receipt: receipt);
  }

  bool bindActivityJob(PandoraChatAttemptToken token, String activityJobId) {
    if (!isCurrent(token) || activityJobId.trim().isEmpty) return false;
    final turn = _state.turn(token.turnId)!;
    final attempt = turn.attempt!;
    if (attempt.activityJobId != null &&
        attempt.activityJobId != activityJobId) {
      return false;
    }
    _emit(_state.copyWith(
        turns: _replacing(turn.copyWith(attempts: [
      ...turn.attempts.take(turn.attempts.length - 1),
      attempt.copyWith(activityJobId: activityJobId),
    ]))));
    return true;
  }

  /// A read-only phone inference can explicitly request cloud handling before
  /// any cloud admission. It keeps the logical request and fences prior text.
  bool prepareCloudFallback(PandoraChatAttemptToken token) {
    if (!isCurrent(token)) return false;
    final attempt = _state.turn(token.turnId)!.attempt!;
    if (attempt.activityJobId != null ||
        attempt.lastSequence != 0 ||
        attempt.cancellationRequested) {
      return false;
    }
    return _update(token,
        phase: PandoraChatPhase.pending, reply: '', clearFailure: true);
  }

  List<Map<String, Object?>> _completedClientHistory() {
    final pairs = <List<Map<String, Object?>>>[];
    var bytes = 0;
    for (final turn in _state.turns.reversed) {
      final source = turn.receipt?.provider;
      if (turn.phase != PandoraChatPhase.completed ||
          !const {'local_device', 'character', 'device'}.contains(source) ||
          turn.text.isEmpty ||
          turn.reply.isEmpty) {
        continue;
      }
      final pair = <Map<String, Object?>>[
        {
          'role': 'user',
          'content': turn.text,
          'logicalTurnId': turn.id,
          'source': source
        },
        {
          'role': 'assistant',
          'content': turn.reply,
          'logicalTurnId': turn.id,
          'source': source
        },
      ];
      final size = utf8.encode(jsonEncode(pair)).length;
      if (bytes + size > 24 * 1024 || pairs.length == 16) break;
      pairs.add(pair);
      bytes += size;
    }
    return pairs.reversed.expand((pair) => pair).toList();
  }

  /// [text] is the full accumulated text; [delta] is an actual provider delta.
  /// [streamSequence] orders chunks without consuming lifecycle [sequence].
  bool stream(
    PandoraChatAttemptToken token, {
    String? text,
    String? delta,
    int? sequence,
    int? streamSequence,
  }) {
    if ((text == null) == (delta == null)) return false;
    if (!_admits(token, null, content: true)) return false;
    final turn = _state.turn(token.turnId)!;
    final attempt = turn.attempt!;
    int? lifecycleAdvance = sequence;
    if (streamSequence != null) {
      if (streamSequence <= attempt.lastStreamSequence ||
          (sequence != null && sequence < attempt.lastSequence)) {
        return false;
      }
      // Many chunks may share one durable lifecycle revision. Only a newer
      // lifecycle event changes lastSequence; a chunk offset never can.
      if (sequence == attempt.lastSequence) lifecycleAdvance = null;
    } else if (!_admits(token, sequence, content: true)) {
      return false;
    }
    return _update(
      token,
      phase: PandoraChatPhase.streaming,
      sequence: lifecycleAdvance,
      streamSequence: streamSequence,
      reply: text ?? '${turn.reply}$delta',
      content: true,
    );
  }

  bool complete(
    PandoraChatAttemptToken token, {
    required String reply,
    String? threadId,
    String? assistantMessageId,
    PandoraChatExecutionReceipt? receipt,
    int? sequence,
    bool reconciled = false,
  }) {
    if (!_validThread(threadId) ||
        !_admits(token, sequence, content: !reconciled)) {
      return false;
    }
    final turn = _state.turn(token.turnId)!;
    // A stopped display cannot be repainted by a late provider result. Explicit
    // readback can settle it as cancelled while retaining the execution receipt.
    if (turn.attempt!.cancellationRequested) {
      return reconciled &&
          cancel(token,
              threadId: threadId, receipt: receipt, sequence: sequence);
    }
    return _update(
      token,
      phase: PandoraChatPhase.completed,
      reply: reply,
      threadId: threadId,
      assistantMessageId: assistantMessageId,
      receipt: receipt,
      sequence: sequence,
      content: !reconciled,
      clearFailure: true,
    );
  }

  bool fail(
    PandoraChatAttemptToken token, {
    required String message,
    String? code,
    bool recoverable = true,
    bool outcomeUnknown = false,
    int? sequence,
    PandoraChatExecutionReceipt? receipt,
  }) =>
      _update(
        token,
        phase: outcomeUnknown
            ? PandoraChatPhase.reconciling
            : recoverable
                ? PandoraChatPhase.failedRecoverably
                : PandoraChatPhase.failedPermanently,
        sequence: sequence,
        receipt: receipt,
        failure: PandoraChatFailure(
          message: message,
          code: code,
          recoverable: recoverable,
          outcomeUnknown: outcomeUnknown,
        ),
      );

  /// This is an explicit continuation intent, separate from Stop. Admission
  /// remains blocked until a verified server receipt acknowledges uncertainty.
  bool requestUnknownAcknowledgement(PandoraChatAttemptToken token) {
    if (!isCurrent(token) ||
        !_state.turn(token.turnId)!.canAcknowledgeUnknownOutcome) {
      return false;
    }
    return _update(token, phase: PandoraChatPhase.acknowledgingUnknown);
  }

  /// Fences content immediately. Keep admission blocked until cancellation or
  /// readback settles the existing server execution.
  bool requestCancellation(PandoraChatAttemptToken token) => _update(
        token,
        phase: PandoraChatPhase.cancelling,
        cancellationRequested: true,
      );

  /// An absent-admission observation cannot release the original request. This
  /// transition reopens only its cancellation projection while the adapter asks
  /// the server for an atomic cancellation tombstone using the original IDs.
  PandoraChatAttemptToken? requestAdmissionCancellation(String turnId) {
    if (_disposed || _state.activeTurnId != null) return null;
    final turn = _state.turn(turnId);
    final attempt = turn?.attempt;
    if (turn == null ||
        attempt == null ||
        turn.failure?.code != 'CHAT_NOT_ADMITTED') {
      return null;
    }
    final token = PandoraChatAttemptToken(
        scopeId: attempt.token.scopeId,
        scopeEpoch: attempt.token.scopeEpoch,
        conversationId: attempt.token.conversationId,
        turnId: turnId,
        attemptId: attempt.token.attemptId,
        generation: attempt.token.generation,
        deliveryEpoch: attempt.token.deliveryEpoch + 1);
    final cancelling = attempt.copyWith(
        token: token,
        phase: PandoraChatPhase.cancelling,
        cancellationRequested: true);
    _emit(_state.copyWith(
        activeTurnId: turnId,
        turns: _replacing(turn.copyWith(
          phase: PandoraChatPhase.cancelling,
          attempts: [
            ...turn.attempts.take(turn.attempts.length - 1),
            cancelling
          ],
        ))));
    return token;
  }

  bool cancel(
    PandoraChatAttemptToken token, {
    String? threadId,
    int? sequence,
    PandoraChatExecutionReceipt? receipt,
  }) =>
      _update(
        token,
        phase: PandoraChatPhase.cancelled,
        threadId: threadId,
        sequence: sequence,
        receipt: receipt,
        cancellationRequested: true,
        clearFailure: true,
      );

  bool cancelQueued(String turnId) {
    if (_disposed || _state.queuedTurnId != turnId) return false;
    final turn = _state.queuedTurn!;
    _emit(
      _state.copyWith(
        queuedTurnId: null,
        turns: _replacing(turn.copyWith(phase: PandoraChatPhase.cancelled)),
      ),
    );
    return true;
  }

  bool supersedeFailure(String turnId) {
    final turn = _state.turn(turnId);
    if (_disposed || turn == null || !turn.canRetry) return false;
    if (turn.failure?.code == 'CHAT_NOT_ADMITTED') return false;
    _emit(
      _state.copyWith(
        turns: _replacing(turn.copyWith(phase: PandoraChatPhase.superseded)),
      ),
    );
    return true;
  }

  bool _update(
    PandoraChatAttemptToken token, {
    required PandoraChatPhase phase,
    int? sequence,
    int? streamSequence,
    String? reply,
    String? threadId,
    String? assistantMessageId,
    PandoraChatFailure? failure,
    PandoraChatExecutionReceipt? receipt,
    bool content = false,
    bool clearFailure = false,
    bool cancellationRequested = false,
  }) {
    if (!_admits(token, sequence, content: content) ||
        !_validThread(threadId)) {
      return false;
    }
    final turn = _state.turn(token.turnId)!;
    final prior = turn.attempt!;
    if (receipt?.outcomeUnknownAcknowledged == true &&
        !((receipt!.routing['executionStatus'] == 'outcome_unknown' &&
                phase == PandoraChatPhase.reconciling) ||
            (receipt.routing['executionStatus'] == 'completed' &&
                (phase == PandoraChatPhase.completed ||
                    phase == PandoraChatPhase.cancelled)))) {
      return false;
    }
    if (turn.outcomeUnknownAcknowledged) {
      // A late failure or an older receipt cannot reopen the original request.
      // Only its genuine verified completion may settle acknowledged ambiguity.
      final verifiedCompletion = receipt?.outcomeUnknownAcknowledged == true &&
          receipt?.routing['executionStatus'] == 'completed' &&
          (phase == PandoraChatPhase.completed ||
              phase == PandoraChatPhase.cancelled);
      if ((receipt != null && !receipt.outcomeUnknownAcknowledged) ||
          (phase != PandoraChatPhase.reconciling && !verifiedCompletion)) {
        return false;
      }
    }
    if (prior.phase == PandoraChatPhase.streaming &&
        phase == PandoraChatPhase.processing) {
      return false;
    }
    if ((prior.phase == PandoraChatPhase.reconciling ||
            prior.phase == PandoraChatPhase.acknowledgingUnknown ||
            prior.phase == PandoraChatPhase.cancelling) &&
        content) {
      return false;
    }
    final updated = prior.copyWith(
      phase: phase,
      lastSequence: sequence ?? prior.lastSequence,
      lastStreamSequence: streamSequence ?? prior.lastStreamSequence,
      finishedAt: phase.isTerminal ? _clock().toUtc() : null,
      failure: clearFailure ? null : failure ?? prior.failure,
      receipt: receipt,
      cancellationRequested:
          prior.cancellationRequested || cancellationRequested,
    );
    _emit(
      _state.copyWith(
        threadId: threadId ?? _state.threadId,
        turns: _replacing(
          turn.copyWith(
            phase: phase,
            attempts: [
              ...turn.attempts.take(turn.attempts.length - 1),
              updated,
            ],
            reply: reply,
            failure: clearFailure ? null : failure ?? turn.failure,
            receipt: receipt ?? turn.receipt,
            assistantMessageId: assistantMessageId,
          ),
        ),
        activeTurnId:
            (phase.isTerminal || phase == PandoraChatPhase.reconciling) &&
                    _state.activeTurnId == turn.id
                ? null
                : _state.activeTurnId,
      ),
    );
    return true;
  }

  /// Starts a distinct history-load epoch. Stale loads, voice and execution
  /// callbacks from the previous conversation can no longer affect the shell.
  PandoraChatLoadToken? beginHistoryLoad(String threadId) {
    if (_disposed || _state.hasPendingWork || threadId.trim().isEmpty) {
      return null;
    }
    final next = PandoraChatSessionState(
      scopeId: _state.scopeId,
      scopeEpoch: _state.scopeEpoch + 1,
      conversationId: _newId(),
      threadId: threadId,
      preferences: _state.preferences,
      historyPhase: PandoraChatHistoryPhase.loading,
      draft: PandoraChatDraftState(revision: _state.draft.revision + 1),
    );
    _emit(next);
    return PandoraChatLoadToken(
      scopeId: _state.scopeId,
      scopeEpoch: _state.scopeEpoch,
      conversationId: _state.conversationId,
      threadId: threadId,
    );
  }

  bool matchesLoad(PandoraChatLoadToken token) =>
      !_disposed &&
      token.scopeId == _state.scopeId &&
      token.scopeEpoch == _state.scopeEpoch &&
      token.conversationId == _state.conversationId &&
      token.threadId == _state.threadId &&
      _state.loadingHistory;

  bool replaceHistory(
    PandoraChatLoadToken token,
    List<PandoraChatHistoryMessage> messages, {
    PandoraChatPreferences? preferences,
    List<PandoraChatTurn> reconstructedTurns = const [],
  }) {
    if (!matchesLoad(token) ||
        messages.any(
          (m) =>
              m.threadId != token.threadId ||
              m.id.isEmpty ||
              !const {'user', 'assistant', 'pandora'}.contains(m.role),
        )) {
      return false;
    }
    final turnIds = <String>{};
    for (final turn in reconstructedTurns) {
      final attempt = turn.attempt;
      if (!turnIds.add(turn.id) ||
          attempt == null ||
          attempt.token.scopeId != token.scopeId ||
          attempt.token.scopeEpoch != token.scopeEpoch ||
          attempt.token.conversationId != token.conversationId ||
          attempt.token.turnId != turn.id) {
        return false;
      }
    }
    final byId = <String, PandoraChatHistoryMessage>{};
    for (final message in messages) {
      final prior = byId[message.id];
      if (prior != null &&
          (prior.text != message.text ||
              prior.role != message.role ||
              prior.turnId != message.turnId)) {
        return false;
      }
      byId[message.id] = message;
    }
    final history = byId.values.toList()
      ..sort((a, b) {
        if (a.sequence != null && b.sequence != null) {
          final order = a.sequence!.compareTo(b.sequence!);
          if (order != 0) return order;
        }
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime == 0 ? a.id.compareTo(b.id) : byTime;
      });
    if (preferences != null && !preferences.isValid) return false;
    _emit(
      _state.copyWith(
        history: history,
        turns: reconstructedTurns,
        historyPhase: PandoraChatHistoryPhase.ready,
        preferences: preferences,
        activeTurnId: null,
        queuedTurnId: null,
      ),
    );
    return true;
  }

  bool failHistoryLoad(PandoraChatLoadToken token) {
    if (!matchesLoad(token)) return false;
    _emit(_state.copyWith(historyPhase: PandoraChatHistoryPhase.failed));
    return true;
  }

  /// Restoration is accepted only before interaction and only in this scope.
  /// Pending/accepted work must already be classified as reconciling by store.
  bool restore(
    PandoraChatSessionState restored, {
    required int expectedRevision,
  }) {
    if (_disposed ||
        _state.revision != expectedRevision ||
        restored.scopeId != _state.scopeId ||
        !restored.historyReady ||
        _state.hasPendingWork ||
        _state.turns.isNotEmpty ||
        _state.history.isNotEmpty ||
        _state.draft.text.isNotEmpty ||
        (restored.history.isNotEmpty && restored.threadId == null) ||
        restored.history.any((m) => m.threadId != restored.threadId)) {
      return false;
    }
    final epoch = max(_state.scopeEpoch, restored.scopeEpoch) + 1;
    final turns = restored.turns.map((turn) {
      final attempts = turn.attempts
          .map(
            (attempt) => PandoraChatAttempt(
              token: PandoraChatAttemptToken(
                scopeId: _state.scopeId,
                scopeEpoch: epoch,
                conversationId: restored.conversationId,
                turnId: turn.id,
                attemptId: attempt.token.attemptId,
                generation: attempt.token.generation,
                deliveryEpoch: attempt.token.deliveryEpoch,
              ),
              phase: attempt.phase,
              startedAt: attempt.startedAt,
              lastSequence: attempt.lastSequence,
              lastStreamSequence: attempt.lastStreamSequence,
              activityJobId: attempt.activityJobId,
              finishedAt: attempt.finishedAt,
              failure: attempt.failure,
              receipt: attempt.receipt,
              supersededByAttemptId: attempt.supersededByAttemptId,
              cancellationRequested: attempt.cancellationRequested,
              deliveryFailures: attempt.deliveryFailures,
            ),
          )
          .toList();
      return turn.copyWith(attempts: attempts);
    }).toList();
    _emit(
      PandoraChatSessionState(
        scopeId: _state.scopeId,
        scopeEpoch: epoch,
        conversationId: restored.conversationId,
        threadId: restored.threadId,
        preferences: restored.preferences,
        draft: restored.draft,
        turns: turns,
        history: restored.history,
      ),
    );
    return true;
  }

  bool newChat({bool resetPreferences = false}) {
    if (_disposed ||
        _state.activeTurnId != null ||
        _state.queuedTurnId != null ||
        _state.hasUnresolvedOutcome ||
        _state.hasUnresolvedAdmission) {
      return false;
    }
    _emit(
      PandoraChatSessionState(
        scopeId: _state.scopeId,
        scopeEpoch: _state.scopeEpoch + 1,
        conversationId: _newId(),
        preferences: resetPreferences
            ? const PandoraChatPreferences.auto()
            : _state.preferences,
        draft: PandoraChatDraftState(revision: _state.draft.revision + 1),
      ),
    );
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
