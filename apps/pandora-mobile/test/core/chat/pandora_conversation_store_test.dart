import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_controller.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/chat/pandora_conversation_store.dart';
import 'package:pandora_mobile/core/local/pandora_local_data_policy.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_contract.dart';
import 'package:pandora_mobile/core/local/pandora_local_store_stub.dart';

final _now = DateTime.utc(2026, 10, 3, 16);

String _activeKey(String scope) =>
    'conversation_active_${sha256.convert(utf8.encode(scope))}';

PandoraChatAttempt _attempt({
  String id = 'attempt-one',
  String turnId = 'turn-one',
  String scope = 'scope-one',
  String conversation = 'conversation-one',
  int epoch = 1,
  int generation = 1,
  int lastStreamSequence = 0,
  PandoraChatPhase phase = PandoraChatPhase.completed,
  PandoraChatFailure? failure,
  String? supersededBy,
}) =>
    PandoraChatAttempt(
      token: PandoraChatAttemptToken(
        scopeId: scope,
        scopeEpoch: epoch,
        conversationId: conversation,
        turnId: turnId,
        attemptId: id,
        generation: generation,
      ),
      phase: phase,
      startedAt: _now,
      lastSequence: 7,
      lastStreamSequence: lastStreamSequence,
      activityJobId: 'job-one',
      failure: failure,
      supersededByAttemptId: supersededBy,
    );

PandoraChatTurn _turn({
  String id = 'turn-one',
  int sequence = 1,
  String text = 'Hi',
  String reply = 'Hello.',
  PandoraChatPhase phase = PandoraChatPhase.completed,
  Map<String, Object?> request = const {
    'message': 'Hi',
    'enterpriseContext': {'route': '/home'},
  },
  List<PandoraChatAttempt>? attempts,
  PandoraChatFailure? failure,
}) =>
    PandoraChatTurn(
      id: id,
      text: text,
      createdAt: _now,
      sequence: sequence,
      phase: phase,
      preferences: const PandoraChatPreferences.auto(reasoningMode: 'deep'),
      request: request,
      attempts: attempts ?? [_attempt(turnId: id, phase: phase)],
      reply: reply,
      userMessageId: 'user-$id',
      assistantMessageId:
          phase == PandoraChatPhase.completed ? 'reply-$id' : null,
      serverSequence: sequence,
      failure: failure,
      receipt: phase == PandoraChatPhase.completed
          ? PandoraChatExecutionReceipt(
              provider: 'provider-one',
              model: 'execution-model',
              providerRequestId: 'provider-request-one',
              assistantMessageId: 'reply-$id',
              usage: const {'inputTokens': 12},
            )
          : null,
    );

PandoraChatSessionState _state({
  String scope = 'scope-one',
  String conversation = 'conversation-one',
  String? thread = 'thread-one',
  int epoch = 1,
  int revision = 1,
  String draft = 'Follow-up draft',
  List<PandoraChatTurn>? turns,
  List<PandoraChatHistoryMessage> history = const [],
  String? active,
  String? queued,
}) =>
    PandoraChatSessionState(
      scopeId: scope,
      scopeEpoch: epoch,
      conversationId: conversation,
      threadId: thread,
      revision: revision,
      draft: PandoraChatDraftState(text: draft, revision: 3),
      preferences: const PandoraChatPreferences.auto(reasoningMode: 'fast'),
      turns: turns ?? [_turn()],
      history: history,
      activeTurnId: active,
      queuedTurnId: queued,
    );

class _ControlledStore extends MemoryPandoraLocalStore {
  _ControlledStore() : super(clock: () => _now);

  final written = <String, Map<String, Object?>>{};
  String? pausePutContaining;
  final putStarted = Completer<void>();
  final releasePut = Completer<void>();
  bool pauseNextRead = false;
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool failNextPut = false;

  @override
  Future<void> putCache({
    required PandoraLocalNamespace namespace,
    required String key,
    required Object? payload,
    required DateTime expiresAt,
    String? sourceRevision,
  }) async {
    if (failNextPut) {
      failNextPut = false;
      throw StateError('Synthetic storage interruption.');
    }
    if (pausePutContaining != null && key.contains(pausePutContaining!)) {
      pausePutContaining = null;
      putStarted.complete();
      await releasePut.future;
    }
    await super.putCache(
      namespace: namespace,
      key: key,
      payload: payload,
      expiresAt: expiresAt,
      sourceRevision: sourceRevision,
    );
    written[key] = Map<String, Object?>.from(
        jsonDecode(PandoraLocalDataPolicy.encodePayload(payload)) as Map);
  }

  @override
  Future<PandoraLocalCacheRecord?> getCache(
    PandoraLocalNamespace namespace,
    String key,
  ) async {
    final value = await super.getCache(namespace, key);
    if (pauseNextRead) {
      pauseNextRead = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return value;
  }
}

PandoraConversationStore _store(PandoraLocalStore backend,
        {String scope = 'scope-one'}) =>
    PandoraConversationStore(backend, scopeId: scope, clock: () => _now);

void main() {
  test(
      'restart preserves canonical thread, row, turn, attempt and draft identity',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    final original = _state(history: [
      PandoraChatHistoryMessage(
        id: 'history-user',
        threadId: 'thread-one',
        role: 'user',
        text: 'Earlier message',
        createdAt: _now.subtract(const Duration(minutes: 1)),
        turnId: 'history-turn',
        attemptId: 'history-attempt',
        sequence: 1,
      ),
      PandoraChatHistoryMessage(
        id: 'history-assistant',
        threadId: 'thread-one',
        role: 'assistant',
        text: 'Earlier reply',
        createdAt: _now.subtract(const Duration(seconds: 59)),
        turnId: 'history-turn',
        attemptId: 'history-attempt',
        sequence: 2,
      ),
    ]);
    expect(await store.save(original), isTrue);
    final restored = (await store.loadActive())!;
    expect(restored.state.scopeId, original.scopeId);
    expect(restored.state.conversationId, original.conversationId);
    expect(restored.state.threadId, 'thread-one');
    expect(restored.state.scopeEpoch, 1);
    expect(restored.state.revision, 1);
    expect(restored.state.draft.text, 'Follow-up draft');
    expect(restored.state.draft.revision, 3);
    expect(restored.state.history.map((row) => row.id),
        ['history-user', 'history-assistant']);
    expect(restored.state.history.first.turnId, 'history-turn');
    expect(restored.state.history.first.attemptId, 'history-attempt');
    final turn = restored.state.turns.single;
    expect(turn.id, 'turn-one');
    expect(turn.userMessageId, 'user-turn-one');
    expect(turn.assistantMessageId, 'reply-turn-one');
    expect(turn.attempt!.token, original.turns.single.attempt!.token);
    expect(turn.attempt!.lastSequence, 7);
    expect(turn.attempt!.activityJobId, 'job-one');
    expect(turn.request, original.turns.single.request);
    expect(() => turn.request['message'] = 'changed', throwsUnsupportedError);
    expect(() => (turn.request['enterpriseContext'] as Map)['route'] = '/other',
        throwsUnsupportedError);
    expect(restored.state.preferences.isAuto, isTrue);
    expect(restored.state.preferences.reasoningMode, 'fast');
    expect(turn.preferences.reasoningMode, 'deep');
    expect(turn.receipt!.model, 'execution-model');
    expect(turn.receipt!.providerRequestId, 'provider-request-one');
    expect(restored.requiresReconciliation, isFalse);
    expect(restored.requiresRequestReviewTurnIds, isEmpty);
    expect((await store.loadThread('thread-one'))!.state.conversationId,
        'conversation-one');
  });

  for (final phase in [
    PandoraChatPhase.pending,
    PandoraChatPhase.accepted,
    PandoraChatPhase.processing,
    PandoraChatPhase.streaming,
    PandoraChatPhase.cancelling,
    PandoraChatPhase.reconciling,
  ]) {
    test('restart reconciles ${phase.name} without another execution',
        () async {
      final backend = _ControlledStore();
      final store = _store(backend);
      await store.save(_state(
        active: 'turn-one',
        turns: [_turn(phase: phase, reply: 'Partial reply')],
      ));
      final snapshot = (await store.loadActive())!;
      final turn = snapshot.state.turns.single;
      expect(snapshot.requiresReconciliation, isTrue);
      expect(snapshot.state.activeTurnId, 'turn-one');
      expect(snapshot.state.queuedTurnId, isNull);
      expect(turn.phase, PandoraChatPhase.reconciling);
      expect(turn.attempt!.phase, PandoraChatPhase.reconciling);
      expect(turn.attempt!.token.attemptId, 'attempt-one');
      expect(turn.reply, 'Partial reply');
      expect(turn.failure!.outcomeUnknown, isTrue);
      expect(turn.canRetry, isFalse);
      expect(snapshot.state.history, isEmpty);
    });
  }

  test('successful retry keeps the same turn and resolved attempt history',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    const oldFailure =
        PandoraChatFailure(message: 'Please try this message again.');
    await store.save(_state(turns: [
      _turn(attempts: [
        _attempt(
          phase: PandoraChatPhase.superseded,
          failure: oldFailure,
          supersededBy: 'attempt-two',
        ),
        _attempt(id: 'attempt-two', generation: 2),
      ]),
    ]));
    final snapshot = (await store.loadActive())!;
    final turn = snapshot.state.turns.single;
    expect(turn.phase, PandoraChatPhase.completed);
    expect(turn.failure, isNull);
    expect(turn.userMessageId, 'user-turn-one');
    expect(turn.attempts.map((attempt) => attempt.token.attemptId),
        ['attempt-one', 'attempt-two']);
    expect(turn.attempts.first.supersededByAttemptId, 'attempt-two');
    expect(turn.attempts.first.failure!.message, oldFailure.message);
    expect(turn.reply, 'Hello.');
    expect(snapshot.state.history, isEmpty);
  });

  test('unsent queued intent remains visible but is not resumed automatically',
      () async {
    final store = _store(_ControlledStore());
    await store.save(_state(
      queued: 'turn-two',
      turns: [
        _turn(),
        _turn(
          id: 'turn-two',
          sequence: 2,
          text: 'A queued follow-up',
          phase: PandoraChatPhase.pending,
          attempts: [],
          reply: '',
        ),
      ],
    ));
    final snapshot = (await store.loadActive())!;
    expect(snapshot.state.queuedTurnId, isNull);
    expect(snapshot.requiresReconciliation, isFalse);
    expect(snapshot.state.turns.last.id, 'turn-two');
    expect(snapshot.state.turns.last.phase, PandoraChatPhase.failedRecoverably);
    expect(snapshot.state.turns.last.attempts, isEmpty);
    expect(snapshot.state.turns.last.failure!.code, 'UNSENT_AFTER_RESTART');
  });

  test('policy-blocked request is never stripped and retried as a new payload',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    final original = _state(turns: [
      _turn(
        phase: PandoraChatPhase.failedRecoverably,
        failure:
            const PandoraChatFailure(message: 'The message could not finish.'),
        request: const {
          'message': 'Hi',
          'credential': 'SYNTHETIC-TEST-MARKER',
        },
      ),
    ]);
    expect(await store.save(original), isTrue);
    final restored = (await store.loadActive())!;
    final turn = restored.state.turns.single;
    expect(turn.requestAvailable, isFalse);
    expect(turn.request, isEmpty);
    expect(turn.canRetry, isFalse);
    expect(turn.phase, PandoraChatPhase.failedPermanently);
    expect(restored.requiresRequestReviewTurnIds, {'turn-one'});
    expect(
        original.turns.single.request['credential'], 'SYNTHETIC-TEST-MARKER');
    expect(
        jsonEncode(backend.written), isNot(contains('SYNTHETIC-TEST-MARKER')));
    // Re-saving and another restart must retain the unavailable-request gate.
    await store.save(restored.state.copyWith(revision: 2));
    final again = (await store.loadActive())!;
    expect(again.state.turns.single.requestAvailable, isFalse);
    expect(again.requiresRequestReviewTurnIds, {'turn-one'});
  });

  test('unknown attachment outcome must reconcile and still requires review',
      () async {
    final store = _store(_ControlledStore());
    await store.save(_state(
      active: 'turn-one',
      turns: [
        _turn(
          phase: PandoraChatPhase.processing,
          reply: '',
          request: const {
            'message': 'Read the image',
            'imageAttachment': {'uri': 'content://temporary/photo-one'},
          },
        ),
      ],
    ));
    final snapshot = (await store.loadActive())!;
    final turn = snapshot.state.turns.single;
    expect(snapshot.requiresReconciliation, isTrue);
    expect(snapshot.requiresRequestReviewTurnIds, {'turn-one'});
    expect(turn.requestAvailable, isFalse);
    expect(turn.request, isEmpty);
    expect(turn.canRetry, isFalse);
    expect(turn.attempt!.token.attemptId, 'attempt-one');
    // Even after readback confirms recoverable failure, no stripped retry.
    expect(
      turn
          .copyWith(
            phase: PandoraChatPhase.failedRecoverably,
            failure: const PandoraChatFailure(
                message: 'The original request failed.'),
          )
          .canRetry,
      isFalse,
    );
  });

  test('bounded inline attachment payload is preserved exactly', () async {
    final store = _store(_ControlledStore());
    const request = <String, Object?>{
      'message': 'Read the note',
      'textAttachment': {
        'name': 'note.txt',
        'content': 'A small attached note.',
        'mimeType': 'text/plain',
      },
    };
    await store.save(_state(turns: [
      _turn(
        phase: PandoraChatPhase.failedRecoverably,
        request: request,
        failure: const PandoraChatFailure(message: 'Please try again.'),
      ),
    ]));
    final snapshot = (await store.loadActive())!;
    expect(snapshot.state.turns.single.requestAvailable, isTrue);
    expect(snapshot.state.turns.single.request, request);
    expect(snapshot.state.turns.single.canRetry, isTrue);
    expect(snapshot.requiresRequestReviewTurnIds, isEmpty);
  });

  test('oversized request records identity and review state without payload',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    await store.save(_state(turns: [
      _turn(
        phase: PandoraChatPhase.failedRecoverably,
        request: {'message': 'Read it', 'attachmentData': 'a' * 50000},
        failure: const PandoraChatFailure(message: 'Please try again.'),
      ),
    ]));
    final snapshot = (await store.loadActive())!;
    expect(snapshot.requiresRequestReviewTurnIds, {'turn-one'});
    expect(snapshot.state.turns.single.requestAvailable, isFalse);
    expect(snapshot.state.turns.single.id, 'turn-one');
    expect(
        utf8
            .encode(jsonEncode(backend.written[_activeKey('scope-one')]))
            .length,
        lessThan(PandoraLocalDataPolicy.maxPayloadBytes));
  });

  test(
      'oversized draft invalidates active cache without restoring a stale draft',
      () async {
    final store = _store(_ControlledStore());
    expect(await store.save(_state()), isTrue);
    expect(await store.save(_state(revision: 2, draft: '文' * 50000)), isFalse);
    expect(await store.loadActive(), isNull);
    expect((await store.loadThread('thread-one'))!.state.draft.text,
        'Follow-up draft');
    expect(await store.save(_state(revision: 3, draft: 'A cacheable draft')),
        isTrue);
    expect((await store.loadActive())!.state.draft.text, 'A cacheable draft');
  });

  test('cache budget evicts only old history while preserving current identity',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    final history = List.generate(
        20,
        (i) => PandoraChatHistoryMessage(
              id: 'history-$i',
              threadId: 'thread-one',
              role: i.isEven ? 'user' : 'assistant',
              text: 'x' * 10000,
              createdAt: _now.add(Duration(seconds: i)),
              sequence: i,
            ));
    expect(await store.save(_state(history: history)), isTrue);
    final snapshot = (await store.loadActive())!;
    expect(snapshot.truncated, isTrue);
    expect(snapshot.state.threadId, 'thread-one');
    expect(snapshot.state.turns.single.id, 'turn-one');
    expect(snapshot.state.draft.text, 'Follow-up draft');
    expect(snapshot.state.history.last.id, 'history-19');
    expect(snapshot.state.history.length, lessThan(history.length));
    expect(
        utf8
            .encode(jsonEncode(backend.written[_activeKey('scope-one')]))
            .length,
        lessThanOrEqualTo(PandoraLocalDataPolicy.maxPayloadBytes));
  });

  test('older or replayed revisions cannot replace the current draft',
      () async {
    final store = _store(_ControlledStore());
    expect(await store.save(_state(revision: 9, draft: 'Latest')), isTrue);
    expect(await store.save(_state(revision: 8, draft: 'Older')), isFalse);
    expect(await store.save(_state(revision: 9, draft: 'Conflicting replay')),
        isFalse);
    expect((await store.loadActive())!.state.draft.text, 'Latest');
  });

  test('reset orders after in-flight write and late saves cannot resurrect it',
      () async {
    final backend = _ControlledStore()
      ..pausePutContaining = 'conversation_active_';
    final store = _store(backend);
    final saving = store.save(_state());
    await backend.putStarted.future;
    final resetting = store.resetActive(scopeEpoch: 2);
    backend.releasePut.complete();
    expect(await saving, isFalse);
    await resetting;
    expect(await store.loadActive(), isNull);
    expect(
        (await store.loadThread('thread-one'))!.state.threadId, 'thread-one');
    expect(await store.save(_state(revision: 99, draft: 'Late callback')),
        isFalse);
    expect(await store.loadActive(), isNull);
  });

  test('shared store instances serialize reset and the new conversation',
      () async {
    final backend = _ControlledStore()
      ..pausePutContaining = 'conversation_thread_';
    final firstStore = _store(backend);
    final secondStore = _store(backend);
    final oldWrite = firstStore.save(_state());
    await backend.putStarted.future;
    final obsoleteWrite = secondStore.save(_state(revision: 2));
    final reset = secondStore.resetActive(scopeEpoch: 2);
    final newWrite = secondStore.save(_state(
      conversation: 'conversation-two',
      thread: null,
      epoch: 2,
      revision: 0,
      draft: 'A new conversation',
      turns: [],
    ));
    backend.releasePut.complete();
    expect(await oldWrite, isFalse);
    expect(await obsoleteWrite, isFalse);
    await reset;
    expect(await newWrite, isTrue);
    final restored = (await firstStore.loadActive())!;
    expect(restored.state.conversationId, 'conversation-two');
    expect(restored.state.threadId, isNull);
    expect(restored.state.turns, isEmpty);
    expect(restored.state.draft.text, 'A new conversation');
    expect(await firstStore.save(_state(revision: 999)), isFalse);
  });

  test('a read racing New Chat cannot deliver the previous active snapshot',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    await store.save(_state());
    backend.pauseNextRead = true;
    final reading = store.loadActive();
    await backend.readStarted.future;
    final reset = store.resetActive(scopeEpoch: 2);
    backend.releaseRead.complete();
    expect(await reading, isNull);
    await reset;
    expect(await store.loadActive(), isNull);
  });

  test('failed disk write does not poison the serial save or reset queue',
      () async {
    final backend = _ControlledStore()..failNextPut = true;
    final store = _store(backend);
    await expectLater(store.save(_state()), throwsStateError);
    expect(await store.save(_state(revision: 2, draft: 'Recovered')), isTrue);
    expect((await store.loadActive())!.state.draft.text, 'Recovered');
    await store.resetActive(scopeEpoch: 2);
    expect(await store.loadActive(), isNull);
  });

  test('scope keys isolate accounts and wrong-scope writes are rejected',
      () async {
    final backend = _ControlledStore();
    final first = _store(backend);
    final second = _store(backend, scope: 'scope-two');
    await first.save(_state());
    expect(await second.loadActive(), isNull);
    expect(await second.loadThread('thread-one'), isNull);
    expect(() => second.save(_state()), throwsFormatException);
    await second.save(_state(
      scope: 'scope-two',
      conversation: 'conversation-two',
      thread: 'thread-two',
      turns: [],
      draft: 'Second account',
    ));
    expect((await first.loadActive())!.state.draft.text, 'Follow-up draft');
    expect((await second.loadActive())!.state.draft.text, 'Second account');
    await first.resetActive(scopeEpoch: 2);
    expect((await second.loadActive())!.state.draft.text, 'Second account');
  });

  test('mismatched persisted scope fails closed without touching another scope',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    await store.save(_state());
    final corrupted = {...backend.written[_activeKey('scope-one')]!};
    corrupted['scopeId'] = 'scope-two';
    await backend.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: _activeKey('scope-one'),
      payload: corrupted,
      expiresAt: _now.add(const Duration(days: 1)),
    );
    expect(await store.loadActive(), isNull);
    expect((await store.loadThread('thread-one'))!.state.scopeId, 'scope-one');
  });

  test('request digest mismatch cannot produce a restored executable retry',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    await store.save(_state());
    final corrupted = {...backend.written[_activeKey('scope-one')]!};
    final turn = (corrupted['turns'] as List).single as Map;
    (turn['request'] as Map)['message'] = 'A different action';
    await backend.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: _activeKey('scope-one'),
      payload: corrupted,
      expiresAt: _now.add(const Duration(days: 1)),
    );
    expect(await store.loadActive(), isNull);
  });

  test(
      'legacy active payload without thread or turn identity is never restored',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    await backend.putCache(
      namespace: PandoraLocalNamespace.recentConversation,
      key: _activeKey('scope-one'),
      payload: const {
        'messages': [
          {'role': 'user', 'text': 'Legacy text without identity'},
        ],
      },
      expiresAt: _now.add(const Duration(days: 1)),
    );
    expect(await store.loadActive(), isNull);
  });

  test('wrong-thread history and cross-generation identity are rejected', () {
    final store = _store(_ControlledStore());
    expect(() => store.save(_state(thread: null)), throwsFormatException);
    expect(
      () => store.save(_state(history: [
        PandoraChatHistoryMessage(
          id: 'history-wrong-thread',
          threadId: 'thread-two',
          role: 'user',
          text: 'Wrong conversation',
          createdAt: _now,
        ),
      ])),
      throwsFormatException,
    );
    expect(
      () => store.save(_state(turns: [
        _turn(attempts: [_attempt(epoch: 2)]),
      ])),
      throwsFormatException,
    );
  });

  test('legacy assistant role retains the same canonical message identity',
      () async {
    final store = _store(_ControlledStore());
    await store.save(_state(history: [
      PandoraChatHistoryMessage(
        id: 'assistant-alias-row',
        threadId: 'thread-one',
        role: 'pandora',
        text: 'Earlier Pandora reply',
        createdAt: _now,
      ),
    ]));
    final message = (await store.loadActive())!.state.history.single;
    expect(message.id, 'assistant-alias-row');
    expect(message.role, 'pandora');
    expect(message.isUser, isFalse);
  });

  test(
      'interrupted first send retains client identity before thread acceptance',
      () async {
    final store = _store(_ControlledStore());
    final turn = PandoraChatTurn(
      id: 'turn-one',
      text: 'First message',
      createdAt: _now,
      sequence: 1,
      phase: PandoraChatPhase.pending,
      preferences: const PandoraChatPreferences.auto(),
      request: const {'message': 'First message'},
      attempts: [_attempt(phase: PandoraChatPhase.pending)],
    );
    expect(
        await store.save(_state(
          thread: null,
          turns: [turn],
          active: 'turn-one',
        )),
        isTrue);
    final snapshot = (await store.loadActive())!;
    expect(snapshot.state.threadId, isNull);
    expect(snapshot.state.conversationId, 'conversation-one');
    expect(snapshot.state.turns.single.id, 'turn-one');
    expect(snapshot.state.turns.single.attempt!.token.attemptId, 'attempt-one');
    expect(snapshot.requiresReconciliation, isTrue);
    expect(snapshot.state.turns.single.canRetry, isFalse);
  });

  test('repeated reset fences every retired conversation at the same epoch',
      () async {
    final store = _store(_ControlledStore());
    await store.save(_state(turns: []));
    await store.resetActive(scopeEpoch: 1);
    await store.save(_state(
      conversation: 'conversation-two',
      thread: null,
      turns: [],
    ));
    await store.resetActive(scopeEpoch: 1);
    expect(await store.save(_state(revision: 99, turns: [])), isFalse);
    expect(await store.loadActive(), isNull);
  });

  for (final status in ['completed', 'cancelled']) {
    test('stopped display preserves $status execution outcome after restart',
        () async {
      final backend = _ControlledStore();
      final store = _store(backend);
      final receipt = PandoraChatExecutionReceipt(
        provider: 'provider-one',
        model: 'execution-model',
        providerRequestId: 'provider-request-one',
        routing: {
          'executionStatus': status,
          'traceDetails': 'SYNTHETIC-INTERNAL-TRACE',
        },
        usage: const {'inputTokens': 25},
      );
      final turn = _turn(phase: PandoraChatPhase.cancelled).copyWith(
        receipt: receipt,
        attempts: [
          _attempt(phase: PandoraChatPhase.cancelled).copyWith(
            receipt: receipt,
            cancellationRequested: true,
          ),
        ],
      );
      await store.save(_state(turns: [turn]));
      final restored = (await store.loadActive())!.state.turns.single;
      expect(restored.phase, PandoraChatPhase.cancelled);
      expect(restored.receipt!.routing, {'executionStatus': status});
      expect(restored.attempt!.receipt!.routing, {'executionStatus': status});
      expect(restored.attempt!.cancellationRequested, isTrue);
      expect(restored.receipt!.usage, isEmpty);
      expect(jsonEncode(backend.written),
          isNot(contains('SYNTHETIC-INTERNAL-TRACE')));
    });
  }

  test('restart preserves chunk offset independently of lifecycle revision',
      () async {
    final store = _store(_ControlledStore());
    await store.save(_state(
      active: 'turn-one',
      turns: [
        _turn(
          phase: PandoraChatPhase.streaming,
          attempts: [
            _attempt(
              phase: PandoraChatPhase.streaming,
              lastStreamSequence: 100,
            ),
          ],
        ),
      ],
    ));
    final snapshot = (await store.loadActive())!;
    final attempt = snapshot.state.turns.single.attempt!;
    expect(attempt.lastSequence, 7);
    expect(attempt.lastStreamSequence, 100);
    expect(attempt.phase, PandoraChatPhase.reconciling);
    expect(
        attempt.copyWith(phase: PandoraChatPhase.completed).lastStreamSequence,
        100);
    await store.save(snapshot.state.copyWith(revision: 2));
    expect(
        (await store.loadActive())!
            .state
            .turns
            .single
            .attempt!
            .lastStreamSequence,
        100);
  });

  test('same-process remount can save after reset and rejects the prior owner',
      () async {
    final backend = _ControlledStore();
    final firstStore = _store(backend);
    final first = PandoraChatController(
      scopeId: 'scope-one',
      initialScopeEpoch: firstStore.nextScopeEpoch,
    );
    first.setDraft('A draft before reset');
    expect(await firstStore.save(first.state), isTrue);
    expect(first.newChat(), isTrue);
    final retiredState = first.state;
    await firstStore.resetActive(scopeEpoch: first.state.scopeEpoch);
    first.dispose();

    final nextStore = _store(backend);
    expect(await nextStore.loadActive(), isNull);
    final next = PandoraChatController(
      scopeId: 'scope-one',
      initialScopeEpoch: nextStore.nextScopeEpoch,
    );
    addTearDown(next.dispose);
    expect(next.state.scopeEpoch, greaterThan(retiredState.scopeEpoch));
    next.setDraft('A draft after remount');
    expect(await nextStore.save(next.state), isTrue);
    expect(await firstStore.save(retiredState), isFalse);
    final snapshot = (await nextStore.loadActive())!;
    expect(snapshot.state.conversationId, next.state.conversationId);
    expect(snapshot.state.draft.text, 'A draft after remount');
  });

  test('confirmed absence and redelivery fence survive subsequent restarts',
      () async {
    final store = _store(_ControlledStore());
    final original = PandoraChatController(
      scopeId: 'scope-one',
      initialScopeEpoch: store.nextScopeEpoch,
    );
    addTearDown(original.dispose);
    original.setDraft('One immutable request');
    final sent = original.submitDraft().dispatch!;
    original.fail(sent.token,
        message: 'Checking receipt.', code: 'LOST_ACK', outcomeUnknown: true);
    expect(original.markNotAdmitted(sent.token), isTrue);
    await store.save(original.state);
    final absentSnapshot = (await store.loadActive())!;
    expect(absentSnapshot.requiresReconciliation, isFalse);
    expect(
        absentSnapshot.state.turns.single.failure!.code, 'CHAT_NOT_ADMITTED');

    final restored = PandoraChatController(
      scopeId: 'scope-one',
      initialScopeEpoch: store.nextScopeEpoch,
    );
    addTearDown(restored.dispose);
    expect(restored.restore(absentSnapshot.state, expectedRevision: 0), isTrue);
    final resent = restored.retry(sent.turn.id).dispatch!;
    expect(resent.token.attemptId, sent.token.attemptId);
    expect(resent.token.generation, 1);
    expect(resent.token.deliveryEpoch, 1);
    expect(resent.request, sent.request);
    expect(resent.isRetry, isFalse);
    await store.save(restored.state);
    final inFlightSnapshot = (await store.loadActive())!;
    expect(inFlightSnapshot.requiresReconciliation, isTrue);
    final attempt = inFlightSnapshot.state.turns.single.attempt!;
    expect(attempt.token.deliveryEpoch, 1);
    expect(attempt.token.attemptId, sent.token.attemptId);
    expect(attempt.deliveryFailures.single.deliveryEpoch, 0);
    expect(attempt.deliveryFailures.single.failure.code, 'LOST_ACK');
    final next = PandoraChatController(scopeId: 'scope-one');
    addTearDown(next.dispose);
    expect(next.restore(inFlightSnapshot.state, expectedRevision: 0), isTrue);
    expect(next.state.turns.single.attempt!.token.deliveryEpoch, 1);
    expect(
        next.state.turns.single.attempt!.deliveryFailures.single.failure.code,
        'LOST_ACK');
    expect(next.complete(resent.token, reply: 'A prior controller callback'),
        isFalse);
  });

  test('missing cached request cannot silently release an unresolved admission',
      () async {
    final store = _store(_ControlledStore());
    final chat = PandoraChatController(scopeId: 'scope-one');
    addTearDown(chat.dispose);
    chat.setDraft('Preserve this intent');
    final first = chat.submitDraft(payload: const {
      'textAttachment': {'localPath': '/temporary/unavailable-note'},
    }).dispatch!;
    chat.fail(first.token, message: 'Checking delivery.', outcomeUnknown: true);
    chat.markNotAdmitted(first.token);
    await store.save(chat.state);
    final snapshot = (await store.loadActive())!;
    expect(snapshot.requiresRequestReviewTurnIds, {first.turn.id});
    expect(snapshot.state.hasUnresolvedAdmission, isTrue);
    expect(snapshot.state.hasPendingWork, isTrue);
    expect(snapshot.state.turns.single.requestAvailable, isFalse);
    expect(snapshot.state.turns.single.canRetry, isFalse);
  });

  test('essential clarification lane survives without raw routing diagnostics',
      () async {
    final backend = _ControlledStore();
    final store = _store(backend);
    final receipt = PandoraChatExecutionReceipt(routing: const {
      'executionStatus': 'completed',
      'conversationLane': 'team_admin',
      'needsClarification': true,
      'rawTrace': 'DO-NOT-CACHE-TRACE',
    });
    await store.save(_state(turns: [
      _turn().copyWith(
        receipt: receipt,
        attempts: [_attempt().copyWith(receipt: receipt)],
      ),
    ]));
    final turn = (await store.loadActive())!.state.turns.single;
    const essential = {
      'executionStatus': 'completed',
      'conversationLane': 'team_admin',
      'needsClarification': true,
    };
    expect(turn.receipt!.routing, essential);
    expect(turn.attempt!.receipt!.routing, essential);
    expect(jsonEncode(backend.written), isNot(contains('DO-NOT-CACHE-TRACE')));
  });

  test(
      'read-only inspection metadata survives both canonical history and turn receipts immutably',
      () async {
    final store = _store(_ControlledStore());
    final inspection = <String, Object?>{
      'required': true,
      'kind': 'core_navigation',
      'action': 'inspect',
      'section': 'platform',
      'request': 'Open platform details',
    };
    final receipt = PandoraChatExecutionReceipt(inspection: inspection);
    final row = PandoraChatHistoryMessage(
        id: 'legacy-inspect',
        threadId: 'thread-one',
        role: 'assistant',
        text: 'Saved result',
        createdAt: _now,
        inspection: inspection);
    inspection['request'] = 'Mutated after admission';
    await store.save(_state(turns: [
      _turn().copyWith(
          receipt: receipt, attempts: [_attempt().copyWith(receipt: receipt)])
    ], history: [
      row
    ]));
    final restored = (await store.loadActive())!.state;
    expect(restored.turns.single.receipt!.inspection!['request'],
        'Open platform details');
    expect(restored.turns.single.attempt!.receipt!.inspection,
        restored.turns.single.receipt!.inspection);
    expect(restored.history.single.inspection,
        restored.turns.single.receipt!.inspection);
    expect(() => restored.history.single.inspection!['request'] = 'Changed',
        throwsUnsupportedError);
  });
}
