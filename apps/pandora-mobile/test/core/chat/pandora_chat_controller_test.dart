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

  PandoraChatExecutionReceipt unknownReceipt({bool acknowledged = false}) =>
      PandoraChatExecutionReceipt(
          outcomeUnknownAcknowledged: acknowledged,
          routing: const {'executionStatus': 'outcome_unknown'});

  test('continuation requires confirmed unknown outcome, not connection loss',
      () {
    final original = send('Create the record');
    chat.accept(original.token, threadId: 'thread-one', sequence: 1);
    chat.fail(original.token,
        message: 'Connection lost', outcomeUnknown: true, recoverable: false);
    expect(chat.state.turns.single.canAcknowledgeUnknownOutcome, isFalse);
    expect(chat.requestUnknownAcknowledgement(original.token), isFalse);
    chat.fail(original.token,
        message: 'Outcome unconfirmed',
        outcomeUnknown: true,
        recoverable: false,
        receipt: unknownReceipt(),
        sequence: 2);
    expect(chat.state.turns.single.canAcknowledgeUnknownOutcome, isTrue);
    expect(chat.requestUnknownAcknowledgement(original.token), isTrue);
    expect(chat.requestUnknownAcknowledgement(original.token), isFalse);
    expect(
        chat.state.turns.single.phase, PandoraChatPhase.acknowledgingUnknown);
    expect(chat.state.turns.single.outcomeUnknownAcknowledged, isFalse);
    expect(chat.state.hasUnresolvedOutcome, isTrue);
    expect(chat.state.turns.single.attempt!.cancellationRequested, isFalse);
    expect(chat.retry(original.turn.id).admitted, isFalse);
    chat.setDraft('A distinct follow-up');
    expect(chat.submitDraft().kind, PandoraChatAdmissionKind.queued);
    expect(chat.takeQueued().admitted, isFalse);
    expect(chat.stream(original.token, delta: 'Stale output', sequence: 3),
        isFalse);
    expect(chat.state.turns.first.reply, isEmpty);
  });

  test('durable acknowledgement opens distinct-turn admission only', () {
    final original = send('Create the record');
    chat.accept(original.token, threadId: 'thread-one', sequence: 1);
    chat.fail(original.token,
        message: 'Outcome unconfirmed',
        outcomeUnknown: true,
        recoverable: false,
        receipt: unknownReceipt(),
        sequence: 2);
    chat.setDraft('Inspect a different record');
    final queued = chat.submitDraft();
    expect(chat.requestUnknownAcknowledgement(original.token), isTrue);
    expect(chat.takeQueued().admitted, isFalse);
    expect(
        chat.fail(original.token,
            message: 'Outcome remains unconfirmed',
            outcomeUnknown: true,
            recoverable: false,
            receipt: unknownReceipt(acknowledged: true),
            sequence: 3),
        isTrue);
    final unresolved = chat.state.turn(original.turn.id)!;
    expect(unresolved.phase, PandoraChatPhase.reconciling);
    expect(unresolved.failure!.outcomeUnknown, isTrue);
    expect(unresolved.receipt!.routing['executionStatus'], 'outcome_unknown');
    expect(unresolved.outcomeUnknownAcknowledged, isTrue);
    expect(unresolved.canRetry, isFalse);
    expect(unresolved.canAcknowledgeUnknownOutcome, isFalse);
    expect(chat.state.hasUnresolvedOutcome, isFalse);
    expect(chat.retry(original.turn.id).admitted, isFalse);
    final next = chat.takeQueued().dispatch!;
    expect(next.token.turnId, queued.turnId);
    expect(next.token.turnId, isNot(original.token.turnId));
    expect(next.threadId, 'thread-one');
    expect(next.token.generation, 1);
    expect(next.request['clientHistory'], isNull);
    expect(chat.state.conversationContext, isEmpty);
    expect(chat.state.activeAttempt, next.token);
  });

  test('acknowledged ambiguity rejects stale failure and settles only old turn',
      () {
    final original = send('Create the record');
    chat.accept(original.token, threadId: 'thread-one', sequence: 1);
    chat.fail(original.token,
        message: 'Acknowledged but unconfirmed',
        outcomeUnknown: true,
        recoverable: false,
        receipt: unknownReceipt(acknowledged: true),
        sequence: 3);
    final next = send('Different task');
    chat.accept(next.token, threadId: 'thread-one', sequence: 1);
    chat.stream(next.token, delta: 'Current response', sequence: 2);
    expect(
        chat.fail(original.token, message: 'Old recoverable failure'), isFalse);
    expect(
        chat.fail(original.token,
            message: 'Older unknown receipt',
            outcomeUnknown: true,
            receipt: unknownReceipt(),
            sequence: 4),
        isFalse);
    expect(chat.processing(original.token, sequence: 4), isFalse);
    expect(chat.cancel(original.token, sequence: 4), isFalse);
    expect(chat.requestCancellation(original.token), isFalse);
    expect(
        chat.complete(original.token, reply: 'Unverified completion'), isFalse);
    expect(
        chat.complete(original.token,
            reply: 'Unverified readback', reconciled: true),
        isFalse);
    expect(
        chat.complete(original.token,
            reply: 'Verified original result',
            assistantMessageId: 'original-assistant',
            reconciled: true,
            sequence: 4,
            receipt: PandoraChatExecutionReceipt(
                outcomeUnknownAcknowledged: true,
                assistantMessageId: 'original-assistant',
                routing: const {'executionStatus': 'completed'})),
        isTrue);
    final settled = chat.state.turn(original.turn.id)!;
    expect(settled.phase, PandoraChatPhase.completed);
    expect(settled.reply, 'Verified original result');
    expect(settled.failure, isNull);
    expect(settled.outcomeUnknownAcknowledged, isTrue);
    expect(settled.sequence, 1);
    expect(settled.canRetry, isFalse);
    expect(chat.state.activeAttempt, next.token);
    expect(chat.state.turn(next.turn.id)!.reply, 'Current response');
    expect(chat.state.turns.map((turn) => turn.id),
        [original.turn.id, next.turn.id]);
    chat.setDraft('Third distinct task');
    expect(chat.submitDraft().kind, PandoraChatAdmissionKind.queued);
    expect(chat.takeQueued().admitted, isFalse);
  });

  test('ordinary Stop does not acknowledge an unknown outcome', () {
    final original = send('Create the record');
    chat.accept(original.token, threadId: 'thread-one', sequence: 1);
    expect(chat.requestCancellation(original.token), isTrue);
    chat.fail(original.token,
        message: 'Outcome unconfirmed',
        outcomeUnknown: true,
        recoverable: false,
        receipt: unknownReceipt(),
        sequence: 2);
    expect(chat.state.hasUnresolvedOutcome, isTrue);
    expect(chat.state.turns.single.outcomeUnknownAcknowledged, isFalse);
    expect(chat.state.turns.single.canAcknowledgeUnknownOutcome, isTrue);
    expect(chat.requestCancellation(original.token), isTrue);
    expect(chat.state.turns.single.outcomeUnknownAcknowledged, isFalse);
    expect(chat.state.hasUnresolvedOutcome, isTrue);
  });

  test('scope reset fences an acknowledgement callback and invalid receipts',
      () {
    final original = send('Create the record');
    chat.accept(original.token, threadId: 'thread-one', sequence: 1);
    chat.fail(original.token,
        message: 'Outcome unconfirmed',
        outcomeUnknown: true,
        recoverable: false,
        receipt: unknownReceipt(),
        sequence: 2);
    expect(
        chat.fail(original.token,
            message: 'Contradictory failure',
            receipt: unknownReceipt(acknowledged: true)),
        isFalse);
    chat.requestUnknownAcknowledgement(original.token);
    chat.dispose();
    chat = PandoraChatController(scopeId: 'different-actor:organization');
    expect(
        chat.fail(original.token,
            message: 'Old acknowledgement',
            outcomeUnknown: true,
            receipt: unknownReceipt(acknowledged: true),
            sequence: 3),
        isFalse);
    expect(chat.state.turns, isEmpty);
    expect(chat.state.scopeId, 'different-actor:organization');
  });

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
      'latest history selection supersedes a pending load and fences its callbacks',
      () {
    final first = chat.beginHistoryLoad('thread-a')!;
    final second = chat.beginHistoryLoad('thread-b');
    expect(second, isNotNull);
    final latest = second!;
    expect(latest.scopeEpoch, greaterThan(first.scopeEpoch));
    expect(latest.conversationId, isNot(first.conversationId));
    expect(chat.state.threadId, 'thread-b');
    expect(chat.matchesLoad(first), isFalse);
    expect(chat.matchesLoad(latest), isTrue);
    expect(chat.submit('Before history').reason, 'history_loading');
    expect(chat.retry('earlier-turn').reason, 'execution_unresolved');

    PandoraChatHistoryMessage row(String thread) => PandoraChatHistoryMessage(
        id: '$thread-message',
        threadId: thread,
        role: 'user',
        text: 'Saved $thread message',
        createdAt: DateTime.utc(2026));
    final loading = chat.state;
    expect(chat.replaceHistory(first, [row('thread-a')]), isFalse);
    expect(chat.failHistoryLoad(first), isFalse);
    expect(chat.state, same(loading));
    expect(chat.replaceHistory(latest, [row('thread-b')]), isTrue);
    final ready = chat.state;
    expect(chat.replaceHistory(first, [row('thread-a')]), isFalse);
    expect(chat.failHistoryLoad(first), isFalse);
    expect(chat.state, same(ready));
    expect(chat.state.history.single.id, 'thread-b-message');
    expect(send('Continue latest').threadId, 'thread-b');
  });

  test('latest history failure cannot be replaced by an older successful load',
      () {
    final first = chat.beginHistoryLoad('thread-a')!;
    final latest = chat.beginHistoryLoad('thread-b')!;
    expect(chat.failHistoryLoad(latest), isTrue);
    final failed = chat.state;
    expect(chat.replaceHistory(first, const []), isFalse);
    expect(chat.failHistoryLoad(first), isFalse);
    expect(chat.state, same(failed));
    expect(chat.state.threadId, 'thread-b');
    expect(chat.submit('Unverified follow-up').reason, 'history_unverified');
    expect(chat.retry('earlier-turn').reason, 'execution_unresolved');
    final retry = chat.beginHistoryLoad('thread-b')!;
    expect(chat.replaceHistory(retry, const []), isTrue);
    expect(send('After verified retry').threadId, 'thread-b');
  });

  for (final blockedBy in [
    'active',
    'queued',
    'unknown outcome',
    'unadmitted'
  ]) {
    test('history selection cannot abandon $blockedBy work', () {
      final current = send('Current request');
      switch (blockedBy) {
        case 'active':
          chat.accept(current.token, threadId: 'current-thread', sequence: 1);
          chat.processing(current.token, sequence: 2);
        case 'queued':
          chat.accept(current.token, threadId: 'current-thread', sequence: 1);
          expect(chat.submit('Next request').kind,
              PandoraChatAdmissionKind.queued);
          chat.complete(current.token, reply: 'Completed', sequence: 2);
          expect(chat.state.activeTurnId, isNull);
          expect(chat.state.queuedTurnId, isNotNull);
        case 'unknown outcome':
          chat.accept(current.token, threadId: 'current-thread', sequence: 1);
          chat.fail(current.token,
              message: 'Outcome unconfirmed',
              outcomeUnknown: true,
              sequence: 2);
          expect(chat.state.activeTurnId, isNull);
          expect(chat.state.hasUnresolvedOutcome, isTrue);
        case 'unadmitted':
          expect(chat.markNotAdmitted(current.token), isTrue);
          expect(chat.state.activeTurnId, isNull);
          expect(chat.state.hasUnresolvedAdmission, isTrue);
      }
      final before = chat.state;
      expect(chat.beginHistoryLoad('another-thread'), isNull);
      expect(chat.state, same(before));
      expect(chat.state.turn(current.token.turnId), isNotNull);
    });
  }

  test('blank history selection leaves the current load and draft untouched',
      () {
    final load = chat.beginHistoryLoad('thread-a')!;
    chat.setDraft('Preserve this draft');
    final before = chat.state;
    for (final id in ['', ' ', '\t\n']) {
      expect(chat.beginHistoryLoad(id), isNull);
      expect(chat.state, same(before));
    }
    expect(chat.matchesLoad(load), isTrue);
    expect(chat.state.draft.text, 'Preserve this draft');
  });

  test('disposed controller cannot replace a pending history load', () {
    final load = chat.beginHistoryLoad('thread-a')!;
    final before = chat.state;
    chat.dispose();
    expect(chat.beginHistoryLoad('thread-b'), isNull);
    expect(chat.replaceHistory(load, const []), isFalse);
    expect(chat.failHistoryLoad(load), isFalse);
    expect(chat.state, same(before));
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

  test('failed history requires a fresh verified load before any admission',
      () {
    final first = chat.beginHistoryLoad('thread-one')!;
    expect(chat.submit('During loading').reason, 'history_loading');
    expect(chat.failHistoryLoad(first), isTrue);
    expect(chat.state.historyPhase, PandoraChatHistoryPhase.failed);
    expect(chat.submit('After failure').reason, 'history_unverified');
    expect(chat.retry('unrelated-turn').reason, 'execution_unresolved');
    expect(chat.takeQueued().reason, 'execution_unresolved');
    expect(chat.state.turns, isEmpty);

    final retry = chat.beginHistoryLoad('thread-one')!;
    expect(retry.scopeEpoch, greaterThan(first.scopeEpoch));
    expect(retry.conversationId, isNot(first.conversationId));
    final row = PandoraChatHistoryMessage(
        id: 'verified-message',
        threadId: 'thread-one',
        role: 'user',
        text: 'Verified earlier message',
        createdAt: DateTime.utc(2026));
    expect(chat.replaceHistory(first, [row]), isFalse);
    expect(chat.failHistoryLoad(first), isFalse);
    expect(chat.state.loadingHistory, isTrue);
    expect(chat.replaceHistory(retry, [row]), isTrue);
    expect(chat.state.historyReady, isTrue);
    expect(send('Continue').threadId, 'thread-one');
    expect(chat.state.history.single.id, 'verified-message');
  });

  test('failed or loading history cannot be restored as a ready snapshot', () {
    for (final phase in [
      PandoraChatHistoryPhase.loading,
      PandoraChatHistoryPhase.failed,
    ]) {
      final unverified = PandoraChatSessionState(
          scopeId: chat.state.scopeId,
          scopeEpoch: 1,
          conversationId: 'unverified-conversation',
          threadId: 'unverified-thread',
          historyPhase: phase);
      expect(chat.restore(unverified, expectedRevision: 0), isFalse);
      expect(chat.state.threadId, isNull);
    }
  });

  test('conversation context orders mixed rows and excludes obsolete receipts',
      () {
    PandoraChatTurn turn(String id, int order,
            {PandoraChatPhase phase = PandoraChatPhase.completed}) =>
        PandoraChatTurn(
            id: id,
            text: '$id user',
            reply: '$id reply',
            createdAt: DateTime.utc(2026),
            sequence: order,
            phase: phase,
            preferences: const PandoraChatPreferences.auto(),
            request: const {},
            userMessageId: '$id-user-id',
            receipt: PandoraChatExecutionReceipt(
                assistantMessageId: '$id-receipt-id'));
    PandoraChatHistoryMessage row(String id, String text, int order, bool user,
            {String? turnId}) =>
        PandoraChatHistoryMessage(
            id: id,
            threadId: 'thread-one',
            role: user ? 'user' : 'assistant',
            text: text,
            createdAt: DateTime.utc(2026),
            sequence: order,
            turnId: turnId);
    final state = PandoraChatSessionState(
        scopeId: chat.state.scopeId,
        scopeEpoch: 1,
        conversationId: 'mixed-conversation',
        threadId: 'thread-one',
        history: [
          row('local-reply', 'Local middle reply', 3, false),
          row('cloud-a-user-id', 'Duplicate user', 10, true),
          row('local-user', 'Local middle', 2, true),
          row('cloud-a-receipt-id', 'Duplicate receipt', 11, false),
          row('failed-history', 'Failed content', 12, false,
              turnId: 'failedRecoverably'),
        ],
        turns: [
          turn('cloud-c', 4),
          turn('cloud-a', 1),
          for (final phase in PandoraChatPhase.values)
            if (phase != PandoraChatPhase.completed)
              turn(phase.name, 5 + phase.index, phase: phase),
        ]);
    expect(state.conversationContext.map((row) => row.text), [
      'cloud-a user',
      'cloud-a reply',
      'Local middle',
      'Local middle reply',
      'cloud-c user',
      'cloud-c reply',
    ]);
    expect(state.conversationContext.map((row) => row.isUser),
        [true, false, true, false, true, false]);
    expect(() => state.conversationContext.clear(), throwsUnsupportedError);
    expect(
        state
            .copyWith(historyPhase: PandoraChatHistoryPhase.failed)
            .conversationContext,
        isEmpty);
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
