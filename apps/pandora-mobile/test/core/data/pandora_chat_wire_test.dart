import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/network/pandora_sse_decoder.dart';

Map<String, dynamic> receipt({String status = 'accepted'}) => {
      'protocolVersion': 2,
      'organizationId': 'scope-a',
      'threadId': 'thread-a',
      'turnId': 'turn-a',
      'attemptId': 'attempt-a',
      'generation': 1,
      'sequence': 2,
      'status': status,
    };

void main() {
  test('only a verified admission cancellation may omit the server thread', () {
    final tombstone = <String, dynamic>{
      ...receipt(status: 'cancelled'),
      'found': true,
      'admitted': false,
      'admissionCancelled': true,
      'threadId': null,
      'activityJobId': null,
      'userMessageId': null,
      'assistantMessageId': null,
      'sequence': 1,
      'retryable': false,
      'cancellationRequested': true,
    };
    final event = PandoraChatWireEvent.fromJson(tombstone);
    expect(event.threadId, isNull);
    expect(event.admissionCancelled, isTrue);
    expect(event.isTerminal, isTrue);
    expect(event.recoverable, isFalse);
    event.requireIdentity(
        organizationId: 'scope-a',
        turnId: 'turn-a',
        attemptId: 'attempt-a',
        generation: 1);
    expect(
        () => event.requireIdentity(
            organizationId: 'scope-a',
            turnId: 'turn-a',
            threadId: 'already-admitted'),
        throwsFormatException);
    for (final inconsistent in <Map<String, dynamic>>[
      {'status': 'accepted'},
      {'admissionCancelled': false},
      {'admitted': true},
      {'found': false},
      {'threadId': 'thread-a'},
      {'activityJobId': 'job-a'},
      {'userMessageId': 'user-a'},
      {'assistantMessageId': 'reply-a'},
      {'generation': 2},
      {'sequence': 0},
      {'retryable': true},
      {'cancellationRequested': false},
      {'textDelta': 'obsolete content'},
      {'reply': 'obsolete content'},
    ]) {
      expect(
          () => PandoraChatWireEvent.fromJson({...tombstone, ...inconsistent}),
          throwsFormatException);
    }
    expect(
        () => PandoraChatWireEvent.fromJson({...receipt(), 'threadId': null}),
        throwsFormatException);
    final cancelledRetry = PandoraChatWireEvent.fromJson({
      ...tombstone,
      'generation': 2,
      'threadId': 'thread-a',
      'userMessageId': 'original-user-message',
    });
    expect(cancelledRetry.admissionCancelled, isTrue);
    expect(cancelledRetry.threadId, 'thread-a');
    expect(cancelledRetry.generation, 2);
    expect(cancelledRetry.userMessageId, 'original-user-message');
    for (final mismatch in <Map<String, dynamic>>[
      {'threadId': null},
      {'userMessageId': null},
      {'threadId': ''},
      {'userMessageId': ''},
    ]) {
      expect(
          () => PandoraChatWireEvent.fromJson({
                ...cancelledRetry.data,
                ...mismatch,
              }),
          throwsFormatException);
    }
  });

  test('SSE joins arbitrary chunks and split Unicode without losing reply text',
      () async {
    final frame = {
      ...receipt(status: 'streaming'),
      'type': 'delta',
      'streamSequence': 1,
      'textDelta': 'Hello 👋\nPandora'
    };
    final bytes =
        utf8.encode(': heartbeat\r\ndata: ${jsonEncode(frame)}\r\n\r\n');
    final events = await decodePandoraSse(Stream.fromIterable(
      bytes.map((byte) => <int>[byte]),
    )).toList();
    expect(events, [frame]);
    expect(PandoraChatWireEvent.fromJson(events.single).textDelta,
        'Hello 👋\nPandora');
  });

  test('SSE rejects an incomplete terminal frame after a disconnect', () async {
    final frame = {...receipt(status: 'completed'), 'reply': 'Finished'};
    await expectLater(
        decodePandoraSse(Stream.value(
          utf8.encode('data: ${jsonEncode(frame)}\n'),
        )).toList(),
        throwsFormatException);
  });

  test('SSE ignores heartbeats and bounds frame and response accumulation',
      () async {
    expect(
        await decodePandoraSse(
                Stream.value(utf8.encode(': still connected\n\n')))
            .toList(),
        isEmpty);
    await expectLater(
        decodePandoraSse(
          Stream.value(utf8.encode('data: ${'x' * 40}\n\n')),
          maxFrameCharacters: 20,
        ).toList(),
        throwsFormatException);
    await expectLater(
        decodePandoraSse(
          Stream.value(utf8.encode(': ${'x' * 40}\n\n')),
          maxResponseBytes: 20,
        ).toList(),
        throwsFormatException);
  });

  test('receipts reject stale attempt, generation, thread and organization',
      () {
    final event = PandoraChatWireEvent.fromJson(receipt());
    event.requireIdentity(
        organizationId: 'scope-a',
        turnId: 'turn-a',
        attemptId: 'attempt-a',
        generation: 1,
        threadId: 'thread-a');
    for (final mismatch in [
      {'organizationId': 'scope-b'},
      {'turnId': 'turn-b'},
      {'attemptId': 'attempt-b'},
      {'generation': 2},
      {'threadId': 'thread-b'},
    ]) {
      expect(
          () => event.requireIdentity(
                organizationId:
                    mismatch['organizationId'] as String? ?? 'scope-a',
                turnId: mismatch['turnId'] as String? ?? 'turn-a',
                attemptId: mismatch['attemptId'] as String? ?? 'attempt-a',
                generation: mismatch['generation'] as int? ?? 1,
                threadId: mismatch['threadId'] as String? ?? 'thread-a',
              ),
          throwsFormatException);
    }
  });

  test('token events require an independent positive integer sequence', () {
    final frame = {
      ...receipt(status: 'streaming'),
      'type': 'delta',
      'textDelta': 'Hi'
    };
    for (final invalid in [null, 0, -1, 1.5, '1']) {
      expect(
          () => PandoraChatWireEvent.fromJson({
                ...frame,
                'streamSequence': invalid,
              }),
          throwsFormatException);
    }
    final event =
        PandoraChatWireEvent.fromJson({...frame, 'streamSequence': 300});
    expect(event.sequence, 2);
    expect(event.streamSequence, 300);
  });

  test('completed receipt retains actual routing without rewriting Auto', () {
    final input = {
      ...receipt(status: 'completed'),
      'reply': 'We can continue here.',
      'routing': {
        'selectionMode': 'auto',
        'provider': 'bedrock',
        'model': 'kimi'
      },
      'usage': {'outputTokens': 9},
      'timings': {'firstVisibleDeltaMs': 312},
      'assistantMessageId': 'message-a',
    };
    final event = PandoraChatWireEvent.fromJson(input);
    (input['routing'] as Map)['model'] = 'another-model';
    expect(event.isTerminal, isTrue);
    expect(event.turn!.routing['selectionMode'], 'auto');
    expect(event.turn!.routing['model'], 'kimi');
    expect(event.turn!.assistantMessageId, 'message-a');
    expect(event.turn!.timings['firstVisibleDeltaMs'], 312);
    expect(() => (event.data['routing'] as Map)['model'] = 'changed',
        throwsUnsupportedError);
  });

  test('unknown side effects remain distinct from a safely retryable failure',
      () {
    final unknown = PandoraChatWireEvent.fromJson({
      ...receipt(status: 'outcome_unknown'),
      'retryable': false,
    });
    expect(unknown.outcomeUnknown, isTrue);
    expect(unknown.outcomeUnknownAcknowledged, isFalse);
    expect(unknown.recoverable, isFalse);
    expect(unknown.isTerminal, isFalse);
    final failed = PandoraChatWireEvent.fromJson({
      ...receipt(status: 'failed_recoverably'),
      'retryable': true,
    });
    expect(failed.recoverable, isTrue);
    expect(failed.isTerminal, isTrue);
    expect(failed.turn, isNull);
  });

  test(
      'unknown receipts cannot become retryable through omitted or stale flags',
      () {
    for (final status in [
      'outcome_unknown',
      'reconciling',
      'reconciliation_required',
    ]) {
      for (final flags in <Map<String, dynamic>>[
        {},
        {'retryable': true, 'recoverable': true},
        {'outcomeUnknownAcknowledged': false},
      ]) {
        final event = PandoraChatWireEvent.fromJson({
          ...receipt(status: status),
          ...flags,
        });
        expect(event.outcomeUnknown, isTrue);
        expect(event.recoverable, isFalse);
        expect(event.isTerminal, isFalse);
        expect(event.outcomeUnknownAcknowledged, isFalse);
      }
    }
  });

  test('durable acknowledgement retains unknown outcome and its exact identity',
      () {
    final acknowledged = PandoraChatWireEvent.fromJson({
      ...receipt(status: 'outcome_unknown'),
      'outcomeUnknownAcknowledged': true,
      'cancellationRequested': true,
      'retryable': false,
    });
    expect(acknowledged.status, 'outcome_unknown');
    expect(acknowledged.outcomeUnknownAcknowledged, isTrue);
    expect(acknowledged.outcomeUnknown, isTrue);
    expect(acknowledged.recoverable, isFalse);
    expect(acknowledged.isTerminal, isFalse);
    expect(acknowledged.turn, isNull);
    acknowledged.requireIdentity(
      organizationId: 'scope-a',
      threadId: 'thread-a',
      turnId: 'turn-a',
      attemptId: 'attempt-a',
      generation: 1,
    );

    final completed = PandoraChatWireEvent.fromJson({
      ...acknowledged.data,
      'status': 'completed',
      'reply': 'The original verified result arrived.',
      'sequence': acknowledged.sequence + 1,
    });
    expect(completed.outcomeUnknownAcknowledged, isTrue);
    expect(completed.outcomeUnknown, isFalse);
    expect(completed.isTerminal, isTrue);
    expect(completed.recoverable, isFalse);
    expect(completed.turn!.reply, 'The original verified result arrived.');
  });

  test('malformed acknowledgement cannot release an unknown execution', () {
    final acknowledged = {
      ...receipt(status: 'outcome_unknown'),
      'outcomeUnknownAcknowledged': true,
      'cancellationRequested': true,
      'retryable': false,
    };
    for (final contradictory in <Map<String, dynamic>>[
      {'outcomeUnknownAcknowledged': 'true'},
      {'outcomeUnknownAcknowledged': 1},
      {'outcomeUnknownAcknowledged': null},
      {'status': 'processing'},
      {'status': 'cancelled'},
      {'status': 'failed_recoverably'},
      {'status': 'completed', 'reply': ''},
      {'retryable': true},
      {'retryable': null},
      {'cancellationRequested': false},
      {'cancellationRequested': null},
    ]) {
      expect(
          () => PandoraChatWireEvent.fromJson({
                ...acknowledged,
                ...contradictory,
              }),
          throwsFormatException);
    }
  });
}
