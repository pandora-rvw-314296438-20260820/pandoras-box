import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_controller.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';

void main() {
  late PandoraChatController chat;
  setUp(() {
    var id = 0;
    chat = PandoraChatController(
      scopeId: 'actor:organization',
      newId: () =>
          '00000000-0000-4000-8000-${(++id).toString().padLeft(12, '0')}',
      clock: () => DateTime.utc(2026, 10, 3),
    );
  });
  tearDown(() => chat.dispose());

  PandoraChatDispatch send(String text) {
    chat.setDraft(text);
    return chat.submitDraft().dispatch!;
  }

  test('send owns a visible turn and clears its draft before returning', () {
    final dispatch = send('Hi');
    expect(chat.state.turns.single.text, 'Hi');
    expect(chat.state.activeAttempt, dispatch.token);
    expect(chat.state.draft.text, isEmpty);
    expect(dispatch.token.generation, 1);
    expect(chat.submitDraft().reason, 'empty');
    expect(chat.state.turns, hasLength(1));
    expect(() => chat.state.turns.clear(), throwsUnsupportedError);
  });

  test('current draft revision rejects previous-frame resubmission', () {
    chat.setDraft('Hi');
    final revision = chat.state.draft.revision;
    expect(chat.submit('Hi', draftRevision: revision).admitted, isTrue);
    expect(chat.submit('Hi', draftRevision: revision).reason, 'stale_draft');
    expect(chat.state.turns, hasLength(1));
  });

  test(
    'one follow-up is visible during delayed acceptance; third stays draft',
    () {
      final first = send('Hi');
      chat.setDraft('Hello');
      final queued = chat.submitDraft();
      expect(queued.kind, PandoraChatAdmissionKind.queued);
      expect(chat.state.activeAttempt, first.token);
      expect(chat.state.queuedTurn!.text, 'Hello');
      chat.setDraft('What next?');
      expect(chat.submitDraft().reason, 'follow_up_already_pending');
      expect(chat.state.draft.text, 'What next?');
      expect(chat.state.turns, hasLength(2));
    },
  );

  test('queue dispatch uses accepted thread and preserves newer draft', () {
    final first = send('Hi');
    chat.setDraft('Hello');
    chat.submitDraft();
    chat.setDraft('Unsent draft');
    chat.accept(first.token, threadId: 'thread-one', sequence: 1);
    chat.complete(first.token, reply: 'Hello.', sequence: 2);
    final next = chat.takeQueued().dispatch!;
    expect(next.threadId, 'thread-one');
    expect(next.message, 'Hello');
    expect(chat.state.draft.text, 'Unsent draft');
    expect(chat.state.queuedTurnId, isNull);
    expect(chat.takeQueued().admitted, isFalse);
  });

  test('stream sequences are monotonic and completion is admitted once', () {
    final d = send('Explain');
    chat.accept(d.token, threadId: 'thread-one', sequence: 1);
    expect(chat.processing(d.token, sequence: 2), isTrue);
    expect(chat.stream(d.token, delta: 'First', sequence: 3), isTrue);
    expect(chat.stream(d.token, delta: ' duplicate', sequence: 3), isFalse);
    expect(chat.processing(d.token, sequence: 4), isFalse);
    expect(chat.stream(d.token, delta: ' reply', sequence: 4), isTrue);
    expect(chat.state.turns.single.reply, 'First reply');
    expect(chat.complete(d.token, reply: 'First reply', sequence: 5), isTrue);
    expect(chat.complete(d.token, reply: 'Ghost', sequence: 6), isFalse);
    expect(chat.state.turns.single.reply, 'First reply');
  });

  test(
    'wrong scope, thread, generation and attempt cannot alter active turn',
    () {
      final d = send('Hi');
      chat.accept(d.token, threadId: 'thread-one', sequence: 1);
      expect(
        chat.complete(
          d.token,
          reply: 'Wrong thread',
          threadId: 'thread-two',
          sequence: 2,
        ),
        isFalse,
      );
      for (final token in [
        PandoraChatAttemptToken(
          scopeId: 'other',
          scopeEpoch: d.token.scopeEpoch,
          conversationId: d.token.conversationId,
          turnId: d.token.turnId,
          attemptId: d.token.attemptId,
          generation: 1,
        ),
        PandoraChatAttemptToken(
          scopeId: d.token.scopeId,
          scopeEpoch: d.token.scopeEpoch,
          conversationId: d.token.conversationId,
          turnId: d.token.turnId,
          attemptId: 'old-attempt',
          generation: 1,
        ),
        PandoraChatAttemptToken(
          scopeId: d.token.scopeId,
          scopeEpoch: d.token.scopeEpoch,
          conversationId: d.token.conversationId,
          turnId: d.token.turnId,
          attemptId: d.token.attemptId,
          generation: 2,
        ),
      ]) {
        expect(chat.complete(token, reply: 'Ghost'), isFalse);
      }
      expect(chat.state.turns.single.reply, isEmpty);
      expect(chat.state.threadId, 'thread-one');
    },
  );

  test('retry keeps one logical/user identity and exact original request', () {
    final payload = <String, Object?>{
      'enterpriseContext': <String, Object?>{'selected': 'first'},
    };
    chat.setDraft('Inspect');
    final first = chat.submitDraft(payload: payload).dispatch!;
    (payload['enterpriseContext']! as Map<String, Object?>)['selected'] =
        'changed';
    chat.accept(
      first.token,
      threadId: 'thread-one',
      userMessageId: 'server-user',
      sequence: 1,
    );
    chat.fail(first.token, message: 'Try again', sequence: 2);
    chat.setPreferences(
      const PandoraChatPreferences.manual(
        provider: 'provider-b',
        model: 'model-b',
        label: 'B',
        reasoningMode: 'deep',
      ),
    );
    final second = chat.retry(first.turn.id).dispatch!;
    expect(second.token.turnId, first.token.turnId);
    expect(second.token.attemptId, isNot(first.token.attemptId));
    expect(second.token.generation, 2);
    expect(second.expectedGeneration, 1);
    expect(second.preferences.isAuto, isTrue);
    expect(second.request, first.request);
    expect((second.request['enterpriseContext'] as Map)['selected'], 'first');
    expect(chat.state.turns.single.userMessageId, 'server-user');
    expect(
      chat.state.turns.single.attempts.first.supersededByAttemptId,
      second.token.attemptId,
    );
    expect(chat.complete(first.token, reply: 'Late old answer'), isFalse);
    chat.accept(second.token, threadId: 'thread-one', sequence: 1);
    chat.complete(second.token, reply: 'Recovered', sequence: 2);
    expect(chat.state.turns, hasLength(1));
    expect(chat.state.turns.single.failure, isNull);
    expect(chat.state.turns.single.reply, 'Recovered');
    expect(
      chat.state.turns.single.attempts.first.failure!.message,
      'Try again',
    );
  });

  test('unrelated successful turn cannot mark a failed turn recovered', () {
    final a = send('A');
    chat.fail(a.token, message: 'A was not completed');
    final b = send('B');
    chat.complete(b.token, reply: 'B completed');
    expect(chat.state.turns.first.phase, PandoraChatPhase.failedRecoverably);
    expect(chat.state.turns.first.failure!.message, 'A was not completed');
    expect(chat.state.turns.last.phase, PandoraChatPhase.completed);
  });

  test(
    'unknown outcome blocks retry and next dispatch until verified readback',
    () {
      final a = send('Create a record');
      chat.accept(a.token, threadId: 'thread-one', sequence: 1);
      chat.fail(a.token, message: 'Checking result', outcomeUnknown: true);
      expect(chat.retry(a.turn.id).admitted, isFalse);
      chat.setDraft('Then inspect it');
      expect(chat.submitDraft().kind, PandoraChatAdmissionKind.queued);
      expect(chat.takeQueued().admitted, isFalse);
      // Local transport failure must not consume the server sequence number.
      expect(
        chat.complete(a.token, reply: 'Created', sequence: 2, reconciled: true),
        isTrue,
      );
      expect(chat.takeQueued().dispatch!.threadId, 'thread-one');
    },
  );

  test(
    'cancellation fences content immediately; next waits for acknowledgment',
    () {
      final a = send('Long reply');
      chat.accept(a.token, threadId: 'thread-one', sequence: 1);
      chat.stream(a.token, delta: 'Partial', sequence: 2);
      expect(chat.requestCancellation(a.token), isTrue);
      expect(chat.stream(a.token, delta: ' late', sequence: 3), isFalse);
      expect(chat.complete(a.token, reply: 'Late', sequence: 4), isFalse);
      chat.setDraft('Next');
      chat.submitDraft();
      expect(chat.takeQueued().admitted, isFalse);
      expect(chat.cancel(a.token, sequence: 3), isTrue);
      final b = chat.takeQueued().dispatch!;
      expect(b.token.turnId, isNot(a.token.turnId));
      expect(chat.complete(a.token, reply: 'Ghost', sequence: 9), isFalse);
      expect(chat.state.activeAttempt, b.token);
    },
  );

  test('verified late completion settles a stopped turn without repaint', () {
    final a = send('Long reply');
    chat.stream(a.token, text: 'Visible partial');
    chat.requestCancellation(a.token);
    expect(
      chat.complete(a.token, reply: 'Unwanted tail', reconciled: true),
      isTrue,
    );
    expect(chat.state.turns.single.phase, PandoraChatPhase.cancelled);
    expect(chat.state.turns.single.reply, 'Visible partial');
  });

  test(
    'Auto preference stays Auto when receipt says another execution model',
    () {
      final a = send('Hi');
      chat.complete(
        a.token,
        reply: 'Hi',
        receipt: PandoraChatExecutionReceipt(
          provider: 'kimi',
          model: 'actual-model',
        ),
      );
      expect(chat.state.preferences.isAuto, isTrue);
      expect(chat.state.turns.single.preferences.isAuto, isTrue);
      expect(chat.state.turns.single.receipt!.model, 'actual-model');
    },
  );

  test('preference changes affect next dispatched turn only', () {
    final a = send('First');
    chat.setDraft('Second');
    chat.submitDraft();
    chat.setPreferences(
      const PandoraChatPreferences.manual(
        provider: 'provider',
        model: 'model',
        label: 'Selected',
        reasoningMode: 'deep',
      ),
    );
    expect(a.preferences.isAuto, isTrue);
    chat.complete(a.token, reply: 'First done');
    final b = chat.takeQueued().dispatch!;
    expect(b.preferences.model, 'model');
    expect(b.preferences.reasoningMode, 'deep');
  });

  test(
    'dictation cannot append into newer text or a different conversation',
    () {
      final a = chat.captureDraftToken();
      chat.setDraft('Typed while voice open');
      expect(chat.applyDraftResult(a, 'stale voice'), isFalse);
      final b = chat.captureDraftToken();
      chat.newChat();
      expect(chat.applyDraftResult(b, 'wrong conversation'), isFalse);
      final c = chat.captureDraftToken();
      expect(chat.applyDraftResult(c, 'Current voice'), isTrue);
      expect(chat.state.draft.text, 'Current voice');
    },
  );

  test('New Chat rejects late history and keeps intentional empty state', () {
    final load = chat.beginHistoryLoad('old-thread')!;
    expect(chat.newChat(), isTrue);
    final message = PandoraChatHistoryMessage(
      id: 'message-1',
      threadId: 'old-thread',
      role: 'user',
      text: 'Old',
      createdAt: DateTime.utc(2026),
    );
    expect(chat.replaceHistory(load, [message]), isFalse);
    expect(chat.state.history, isEmpty);
    expect(chat.state.threadId, isNull);
  });

  test(
    'history preserves IDs, deduplicates replay and orders server sequence',
    () {
      final load = chat.beginHistoryLoad('thread-one')!;
      PandoraChatHistoryMessage row(String id, String role, int sequence) =>
          PandoraChatHistoryMessage(
            id: id,
            threadId: 'thread-one',
            role: role,
            text: id,
            createdAt: DateTime.utc(2026),
            sequence: sequence,
            turnId: 'canonical-turn',
          );
      final user = row('user-message', 'user', 1);
      final assistant = row('assistant-message', 'assistant', 2);
      expect(chat.replaceHistory(load, [assistant, user, user]), isTrue);
      expect(chat.state.history.map((m) => m.id), [
        'user-message',
        'assistant-message',
      ]);
      expect(chat.state.history.first.turnId, 'canonical-turn');
      expect(send('Follow-up').threadId, 'thread-one');
    },
  );

  test('conflicting or cross-thread history fails closed', () {
    final load = chat.beginHistoryLoad('thread-one')!;
    final row = PandoraChatHistoryMessage(
      id: 'id',
      threadId: 'different-thread',
      role: 'assistant',
      text: 'Wrong',
      createdAt: DateTime.utc(2026),
    );
    expect(chat.replaceHistory(load, [row]), isFalse);
    expect(chat.state.history, isEmpty);
  });

  test('completed and permanently failed requests cannot retry', () {
    final a = send('A');
    chat.complete(a.token, reply: 'Done');
    expect(chat.retry(a.turn.id).admitted, isFalse);
    final b = send('B');
    chat.fail(b.token, message: 'Not allowed', recoverable: false);
    expect(chat.retry(b.turn.id).admitted, isFalse);
  });

  test('bounded restart history cannot reuse an earlier local turn sequence',
      () {
    final restored = PandoraChatSessionState(
      scopeId: chat.state.scopeId,
      scopeEpoch: 1,
      conversationId: 'restored-conversation',
      threadId: 'restored-thread',
      turns: [
        PandoraChatTurn(
          id: 'retained-turn',
          text: 'The latest retained message',
          createdAt: DateTime.utc(2026, 10, 3),
          sequence: 99,
          phase: PandoraChatPhase.completed,
          preferences: const PandoraChatPreferences.auto(),
          request: const {'message': 'The latest retained message'},
          reply: 'The latest retained reply',
        ),
      ],
    );
    expect(chat.restore(restored, expectedRevision: 0), isTrue);
    final next = send('Continue the conversation');
    expect(next.turn.sequence, 100);
    expect(next.threadId, 'restored-thread');
    expect(chat.state.turns.map((turn) => turn.sequence), [99, 100]);
  });

  test('many chunks cannot consume the terminal lifecycle revision', () {
    final dispatch = send('Explain in detail');
    chat.accept(dispatch.token, threadId: 'thread-one', sequence: 1);
    chat.processing(dispatch.token, sequence: 2);
    for (var chunk = 1; chunk <= 100; chunk++) {
      expect(
          chat.stream(
            dispatch.token,
            delta: '.',
            sequence: 2,
            streamSequence: chunk,
          ),
          isTrue);
    }
    final attempt = chat.state.turns.single.attempt!;
    expect(attempt.lastSequence, 2);
    expect(attempt.lastStreamSequence, 100);
    expect(
        chat.stream(
          dispatch.token,
          delta: 'Duplicate',
          sequence: 2,
          streamSequence: 100,
        ),
        isFalse);
    expect(
        chat.stream(
          dispatch.token,
          delta: 'Old lifecycle',
          sequence: 1,
          streamSequence: 101,
        ),
        isFalse);
    expect(chat.state.turns.single.reply, '.' * 100);
    expect(chat.complete(dispatch.token, reply: 'Done.', sequence: 3), isTrue);
    expect(chat.state.turns.single.phase, PandoraChatPhase.completed);
    expect(chat.state.turns.single.attempt!.lastSequence, 3);
    expect(chat.state.turns.single.attempt!.lastStreamSequence, 100);
  });

  test('chunk offsets cannot block cancellation acknowledgement', () {
    final dispatch = send('A long answer');
    chat.accept(dispatch.token, threadId: 'thread-one', sequence: 1);
    chat.processing(dispatch.token, sequence: 2);
    chat.stream(dispatch.token, text: 'A partial answer', streamSequence: 100);
    expect(chat.requestCancellation(dispatch.token), isTrue);
    expect(
        chat.stream(
          dispatch.token,
          delta: 'A late chunk',
          streamSequence: 101,
        ),
        isFalse);
    expect(chat.cancel(dispatch.token, sequence: 3), isTrue);
    expect(chat.state.turns.single.phase, PandoraChatPhase.cancelled);
    expect(chat.state.turns.single.attempt!.lastSequence, 3);
  });

  test('a stale attempt cannot win with a higher stream offset', () {
    final first = send('Try this');
    chat.accept(first.token, threadId: 'thread-one', sequence: 1);
    chat.fail(first.token, message: 'Please retry.', sequence: 2);
    final second = chat.retry(first.turn.id).dispatch!;
    chat.accept(second.token, threadId: 'thread-one', sequence: 1);
    expect(
        chat.stream(
          first.token,
          delta: 'A stale result',
          sequence: 2,
          streamSequence: 1000,
        ),
        isFalse);
    expect(
        chat.stream(
          second.token,
          delta: 'Current reply',
          sequence: 1,
          streamSequence: 1,
        ),
        isTrue);
    expect(chat.state.turns.single.reply, 'Current reply');
    expect(chat.state.turns.single.attempt!.lastStreamSequence, 1);
    expect(chat.complete(second.token, reply: 'Current reply', sequence: 2),
        isTrue);
  });

  test('restore preserves stream cursor and can settle at lifecycle revision 3',
      () {
    final dispatch = send('A streaming reply');
    chat.accept(dispatch.token, threadId: 'thread-one', sequence: 1);
    chat.processing(dispatch.token, sequence: 2);
    chat.stream(dispatch.token, text: 'Partial', streamSequence: 100);
    chat.fail(dispatch.token,
        message: 'Checking result.', outcomeUnknown: true);
    final restored = PandoraChatController(scopeId: chat.state.scopeId);
    addTearDown(restored.dispose);
    expect(restored.restore(chat.state, expectedRevision: 0), isTrue);
    final attempt = restored.state.turns.single.attempt!;
    expect(attempt.lastSequence, 2);
    expect(attempt.lastStreamSequence, 100);
    expect(
        restored.stream(
          dispatch.token,
          delta: 'A previous controller callback',
          streamSequence: 101,
        ),
        isFalse);
    expect(
        restored.complete(
          attempt.token,
          reply: 'Verified completion',
          sequence: 3,
          reconciled: true,
        ),
        isTrue);
    expect(restored.state.turns.single.reply, 'Verified completion');
  });

  test(
      'verified initial absence resends identical wire IDs with a new delivery fence',
      () {
    chat.setDraft('Preserve this request');
    final first = chat.submitDraft(payload: const {
      'textAttachment': {'name': 'note.txt', 'content': 'The original note'},
    }).dispatch!;
    chat.fail(first.token,
        message: 'Checking delivery.',
        code: 'TRANSPORT_OFFLINE',
        outcomeUnknown: true);
    expect(chat.retry(first.turn.id).admitted, isFalse);
    expect(chat.markNotAdmitted(first.token), isTrue);
    expect(chat.state.turns.single.failure!.code, 'CHAT_NOT_ADMITTED');
    chat.setPreferences(const PandoraChatPreferences.manual(
      provider: 'other-provider',
      model: 'other-model',
      label: 'Other',
    ));
    chat.setDraft('A later unsent draft');
    final resent = chat.retry(first.turn.id).dispatch!;
    expect(resent.token.turnId, first.token.turnId);
    expect(resent.token.attemptId, first.token.attemptId);
    expect(resent.token.generation, 1);
    expect(resent.token.deliveryEpoch, 1);
    expect({first.token, resent.token}, hasLength(2));
    expect(resent.isRetry, isFalse);
    expect(resent.expectedGeneration, isNull);
    expect(resent.request, first.request);
    expect(resent.preferences.isAuto, isTrue);
    expect(chat.state.draft.text, 'A later unsent draft');
    expect(chat.state.turns, hasLength(1));
    expect(chat.state.turns.single.attempts, hasLength(1));
    expect(chat.state.turns.single.failure, isNull);
    final delivery = chat.state.turns.single.attempt!.deliveryFailures.single;
    expect(delivery.deliveryEpoch, 0);
    expect(delivery.failure.code, 'TRANSPORT_OFFLINE');
    expect(() => chat.state.turns.single.attempt!.deliveryFailures.clear(),
        throwsUnsupportedError);
    expect(chat.accept(first.token, threadId: 'wrong-thread', sequence: 1),
        isFalse);
    expect(chat.stream(first.token, delta: 'Old delivery', streamSequence: 100),
        isFalse);
    expect(chat.complete(first.token, reply: 'Old delivery'), isFalse);
    expect(chat.fail(first.token, message: 'Old failure'), isFalse);
    expect(
        chat.accept(resent.token,
            threadId: 'thread-one',
            userMessageId: 'one-user-message',
            sequence: 1),
        isTrue);
    expect(chat.complete(resent.token, reply: 'Received once.', sequence: 2),
        isTrue);
    expect(chat.state.turns.single.userMessageId, 'one-user-message');
    expect(
        chat.state.turns.single.attempt!.deliveryFailures.single.failure.code,
        'TRANSPORT_OFFLINE');
  });

  test('lost retry acknowledgement retransmits the same retry generation', () {
    final first = send('Run the original request');
    chat.accept(first.token,
        threadId: 'thread-one',
        userMessageId: 'original-user-message',
        sequence: 1);
    chat.fail(first.token,
        message: 'A confirmed provider failure.', sequence: 2);
    final retry = chat.retry(first.turn.id).dispatch!;
    chat.fail(retry.token,
        message: 'Checking the retry.',
        code: 'RETRY_ACK_LOST',
        outcomeUnknown: true);
    expect(chat.retry(first.turn.id).admitted, isFalse);
    // The adapter has verified the exact prior attempt remains failed, with no
    // admission of this attempted generation. This is not a fresh execution.
    expect(chat.markNotAdmitted(retry.token), isTrue);
    final resent = chat.retry(first.turn.id).dispatch!;
    expect(resent.token.attemptId, retry.token.attemptId);
    expect(resent.token.generation, 2);
    expect(resent.token.deliveryEpoch, retry.token.deliveryEpoch + 1);
    expect(resent.isRetry, isTrue);
    expect(resent.expectedGeneration, 1);
    expect(resent.request, retry.request);
    expect(chat.state.turns, hasLength(1));
    expect(chat.state.turns.single.userMessageId, 'original-user-message');
    expect(chat.state.turns.single.attempts, hasLength(2));
    expect(chat.state.turns.single.attempts.first.supersededByAttemptId,
        retry.token.attemptId);
    expect(
        chat.complete(retry.token, reply: 'Late retry response', sequence: 20),
        isFalse);
    expect(
        chat.stream(retry.token,
            delta: 'Late retry chunk', streamSequence: 100),
        isFalse);
    expect(
        chat.accept(resent.token, threadId: 'thread-one', sequence: 1), isTrue);
    expect(chat.complete(resent.token, reply: 'Recovered once.', sequence: 2),
        isTrue);
    expect(
        chat.state.turns.single.attempt!.deliveryFailures.single.failure.code,
        'RETRY_ACK_LOST');
  });

  test('known admission or requested cancellation cannot become not admitted',
      () {
    final withJob = send('First');
    chat.accept(withJob.token, activityJobId: 'known-job');
    expect(chat.markNotAdmitted(withJob.token), isFalse);
    chat.fail(withJob.token, message: 'Finished unsuccessfully.');
    final withSequence = send('Second');
    chat.accept(withSequence.token, threadId: 'thread-one', sequence: 1);
    expect(chat.markNotAdmitted(withSequence.token), isFalse);
    chat.fail(withSequence.token,
        message: 'Finished unsuccessfully.', sequence: 2);
    final stopped = send('Third');
    chat.requestCancellation(stopped.token);
    expect(chat.markNotAdmitted(stopped.token), isFalse);
    expect(chat.state.turns.last.phase, PandoraChatPhase.cancelling);
  });

  test(
      'unadmitted first turn holds follow-up until the original thread is bound',
      () {
    final first = send('Hi');
    chat.fail(first.token, message: 'Checking delivery.', outcomeUnknown: true);
    expect(chat.markNotAdmitted(first.token), isTrue);
    expect(chat.state.hasUnresolvedAdmission, isTrue);
    expect(chat.state.hasPendingWork, isTrue);
    expect(chat.newChat(), isFalse);
    expect(chat.beginHistoryLoad('unrelated-thread'), isNull);
    expect(chat.supersedeFailure(first.turn.id), isFalse);
    chat.setDraft('Hello');
    expect(chat.submitDraft().kind, PandoraChatAdmissionKind.queued);
    expect(chat.takeQueued().admitted, isFalse);
    final resent = chat.retry(first.turn.id).dispatch!;
    expect(resent.token.attemptId, first.token.attemptId);
    expect(resent.token.generation, 1);
    expect(resent.isRetry, isFalse);
    expect(chat.state.queuedTurn!.text, 'Hello');
    expect(chat.takeQueued().admitted, isFalse);
    expect(
        chat.accept(resent.token,
            threadId: 'original-thread',
            userMessageId: 'original-user',
            sequence: 1),
        isTrue);
    expect(chat.complete(resent.token, reply: 'Hi.', sequence: 2), isTrue);
    final followUp = chat.takeQueued().dispatch!;
    expect(followUp.threadId, 'original-thread');
    expect(followUp.message, 'Hello');
    expect(chat.state.turns, hasLength(2));
  });

  test(
      'atomic admission cancellation holds the turn until receipt and fences the original delivery',
      () {
    final first = send('Do not run this');
    chat.fail(first.token, message: 'Checking delivery', outcomeUnknown: true);
    expect(chat.markNotAdmitted(first.token), isTrue);
    final cancel = chat.requestAdmissionCancellation(first.turn.id)!;
    expect(cancel.turnId, first.token.turnId);
    expect(cancel.attemptId, first.token.attemptId);
    expect(cancel.generation, 1);
    expect(cancel.deliveryEpoch, 1);
    expect(chat.state.hasPendingWork, isTrue);
    expect(chat.accept(first.token, threadId: 'late-thread', sequence: 1),
        isFalse);
    expect(chat.newChat(), isFalse);
    expect(chat.cancel(cancel, sequence: 1), isTrue);
    expect(chat.state.threadId, isNull);
    expect(chat.state.hasPendingWork, isFalse);
    expect(chat.state.turns.single.failure, isNull);
    expect(chat.newChat(), isTrue);
  });

  test(
      'cancelled accepted receipt binds the canonical first thread before a follow-up',
      () {
    final first = send('First');
    chat.requestCancellation(first.token);
    chat.setDraft('Next');
    chat.submitDraft();
    expect(chat.cancel(first.token, threadId: 'accepted-thread', sequence: 2),
        isTrue);
    expect(chat.takeQueued().dispatch!.threadId, 'accepted-thread');
  });
}
