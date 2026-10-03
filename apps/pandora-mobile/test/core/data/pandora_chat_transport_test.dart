import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_controller.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_state.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _organization = '11111111-1111-4111-8111-111111111111';
const _thread = '22222222-2222-4222-8222-222222222222';
const _user = '33333333-3333-4333-8333-333333333333';

typedef _Handler = FutureOr<http.StreamedResponse> Function(
    http.BaseRequest request, Map<String, dynamic> body);

/// Every request is intercepted in memory, including this fabricated auth
/// exchange. The fixture cannot authenticate to a real service.
class _ChatTransport {
  _ChatTransport(this.handle);
  final _Handler handle;
  final paths = <String>[];
  final requests = <Map<String, dynamic>>[];
  late final SupabaseClient client;

  Future<void> initialize() async {
    final claims = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': _user,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })))
        .replaceAll('=', '');
    client = SupabaseClient(
      'https://transport.invalid',
      'test-placeholder',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient.streaming((request, stream) async {
        final text = await stream.bytesToString();
        final body = text.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(text) as Map<String, dynamic>;
        if (request.url.path == '/auth/v1/token') {
          return _json({
            'access_token': 'eyJhbGciOiJub25lIn0.$claims.fixture',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'test-placeholder',
            'user': {
              'id': _user,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'fixture@example.invalid',
              'created_at': '2026-10-03T00:00:00Z',
              'app_metadata': <String, dynamic>{},
              'user_metadata': <String, dynamic>{},
            },
          });
        }
        paths.add(request.url.path);
        requests.add(body);
        final response = await handle(request, body);
        return http.StreamedResponse(response.stream, response.statusCode,
            request: request,
            headers: response.headers,
            contentLength: response.contentLength);
      }),
    );
    await client.auth.signInWithPassword(
        email: 'fixture@example.invalid', password: 'test-placeholder');
  }

  PandoraIntelligenceApi get api =>
      PandoraIntelligenceApi(client: client, organizationId: _organization);
}

http.StreamedResponse _json(Object value, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), status,
        headers: {'content-type': 'application/json'});

http.StreamedResponse _sse(Stream<List<int>> bytes) =>
    http.StreamedResponse(bytes, 200,
        headers: {'content-type': 'text/event-stream; charset=utf-8'});

List<int> _frame(Map<String, dynamic> value) =>
    utf8.encode('data: ${jsonEncode(value)}\n\n');

Map<String, dynamic> _receipt(
  Map<String, dynamic> request, {
  String status = 'accepted',
  int sequence = 1,
}) =>
    {
      'protocolVersion': 2,
      'organizationId': _organization,
      'threadId': request['threadId'] ?? _thread,
      'turnId': request['clientTurnId'],
      'attemptId': request['clientAttemptId'],
      'generation': request['generation'],
      'activityJobId': 'activity-fixture',
      'userMessageId': 'user-message-fixture',
      'type': status,
      'status': status,
      'sequence': sequence,
      if (status == 'completed')
        'reply': 'We are continuing this conversation.',
    };

PandoraChatDispatch _dispatch() {
  final controller = PandoraChatController(scopeId: _organization);
  addTearDown(controller.dispose);
  return controller.submit('Hi', payload: {
    'clientHistory': [
      {
        'role': 'user',
        'content': 'Earlier greeting',
        'logicalTurnId': '44444444-4444-4444-8444-444444444444',
        'source': 'local_device'
      },
      {
        'role': 'assistant',
        'content': 'Earlier response',
        'logicalTurnId': '44444444-4444-4444-8444-444444444444',
        'source': 'local_device'
      },
    ],
  }).dispatch!;
}

void main() {
  test(
      'one admission streams immediately, deduplicates tokens, then accepts durable cancellation',
      () async {
    final bytes = StreamController<List<int>>();
    final requestArrived = Completer<void>();
    final fixture = _ChatTransport((request, body) {
      expect(request.headers['accept'], 'text/event-stream');
      expect(request.headers['x-organization-id'], _organization);
      requestArrived.complete();
      return _sse(bytes.stream);
    });
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    final dispatch = _dispatch();
    final events = <PandoraChatWireEvent>[];
    final accepted = Completer<void>();
    final finished = Completer<void>();
    fixture.api.executeChatTurn(dispatch).listen((event) {
      events.add(event);
      if (!accepted.isCompleted) accepted.complete();
    }, onError: (Object error, StackTrace stack) {
      if (!finished.isCompleted) finished.completeError(error, stack);
    }, onDone: () {
      if (!finished.isCompleted) finished.complete();
    });
    await requestArrived.future;
    final request = fixture.requests.single;
    expect(request['operation'], 'send');
    expect(request['protocolVersion'], 2);
    expect(request['clientHistory'], dispatch.request['clientHistory']);
    bytes.add(_frame(_receipt(request)));
    await accepted.future;
    expect(events.single.status, 'accepted');
    expect(finished.isCompleted, isFalse);
    bytes.add(_frame(_receipt(request, status: 'streaming', sequence: 2)));
    for (var i = 1; i <= 40; i++) {
      final delta = {
        ..._receipt(request, status: 'streaming', sequence: 2),
        'type': 'delta',
        'streamSequence': i,
        'textDelta': 'x'
      };
      bytes.add(_frame(delta));
      bytes.add(_frame(delta));
    }
    bytes.add(_frame(_receipt(request, status: 'cancelled', sequence: 3)));
    await bytes.close();
    await finished.future;
    expect(events.where((event) => event.type == 'delta').length, 40);
    expect(events.last.status, 'cancelled');
    expect(events.last.sequence, 3);
    expect(fixture.paths, ['/functions/v1/pandora-intelligence-chat']);
  });

  test(
      'a new conversation binds its first accepted thread for every later frame',
      () async {
    final fixture = _ChatTransport((_, request) => _sse(Stream.fromIterable([
          _frame(_receipt(request)),
          _frame({
            ..._receipt(request, status: 'completed', sequence: 2),
            'threadId': 'another-thread'
          }),
        ])));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    final seen = <String>[];
    await expectLater(
        fixture.api.executeChatTurn(_dispatch()).map((event) {
          seen.add(event.status);
          return event;
        }).toList(),
        throwsA(isA<PandoraIntelligenceException>()
            .having((error) => error.outcomeUnknown, 'outcomeUnknown', isTrue)
            .having((error) => error.code, 'code', 'CHAT_PROTOCOL_INVALID')));
    expect(seen, ['accepted']);
    expect(fixture.requests.length, 1);
  });

  test(
      'disconnect after admission reports unknown outcome without a duplicate request',
      () async {
    final fixture = _ChatTransport(
        (_, request) => _sse(Stream.value(_frame(_receipt(request)))));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    await expectLater(
        fixture.api.executeChatTurn(_dispatch()).toList(),
        throwsA(isA<PandoraIntelligenceException>().having(
            (error) => error.outcomeUnknown, 'outcomeUnknown', isTrue)));
    expect(fixture.requests.length, 1);
  });

  test(
      'readback and cancellation send control identity without readmitting work',
      () async {
    final fixture = _ChatTransport((_, request) {
      if (request['operation'] == 'readback') return _json({'found': false});
      return _json(_receipt({...request, 'clientAttemptId': 'attempt-3'},
          status: 'cancelled', sequence: 7));
    });
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    expect(await fixture.api.readChatTurn(turnId: 'turn-3'), isNull);
    final cancelled = await fixture.api.cancelChatTurn(
        turnId: 'turn-3', generation: 3, attemptId: 'attempt-3');
    expect(cancelled.status, 'cancelled');
    expect(fixture.requests, [
      {'protocolVersion': 2, 'operation': 'readback', 'clientTurnId': 'turn-3'},
      {
        'protocolVersion': 2,
        'operation': 'cancel',
        'clientTurnId': 'turn-3',
        'clientAttemptId': 'attempt-3',
        'generation': 3,
        'expectedGeneration': 3
      },
    ]);
  });

  test('explicit acknowledgement preserves unknown outcome across readback',
      () async {
    final fixture = _ChatTransport((request, body) {
      expect(request.headers['x-organization-id'], _organization);
      return _json({
        ..._receipt({
          ...body,
          'clientAttemptId': 'attempt-3',
          'generation': 3,
        }, status: 'outcome_unknown', sequence: 8),
        'outcomeUnknownAcknowledged': true,
        'cancellationRequested': true,
        'retryable': false,
      });
    });
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    final acknowledged = await fixture.api.cancelChatTurn(
      turnId: 'turn-3',
      generation: 3,
      attemptId: 'attempt-3',
      acknowledgeUnknown: true,
    );
    expect(acknowledged.status, 'outcome_unknown');
    expect(acknowledged.outcomeUnknownAcknowledged, isTrue);
    expect(acknowledged.recoverable, isFalse);
    expect(acknowledged.isTerminal, isFalse);
    final restored = await fixture.api.readChatTurn(turnId: 'turn-3');
    expect(restored!.data, acknowledged.data);
    expect(fixture.requests, [
      {
        'protocolVersion': 2,
        'operation': 'cancel',
        'clientTurnId': 'turn-3',
        'clientAttemptId': 'attempt-3',
        'generation': 3,
        'expectedGeneration': 3,
        'acknowledgeUnknown': true,
      },
      {'protocolVersion': 2, 'operation': 'readback', 'clientTurnId': 'turn-3'},
    ]);
  });

  test('acknowledgement requires an exact attempt and ordinary Stop omits it',
      () async {
    final fixture = _ChatTransport((_, body) => _json({
          ..._receipt(body, status: 'outcome_unknown', sequence: 7),
          'outcomeUnknownAcknowledged': false,
          'cancellationRequested': true,
          'retryable': false,
        }));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    for (final attempt in <String?>[null, '', ' ']) {
      await expectLater(
          fixture.api.cancelChatTurn(
            turnId: 'turn-3',
            generation: 3,
            attemptId: attempt,
            acknowledgeUnknown: true,
          ),
          throwsFormatException);
    }
    expect(fixture.requests, isEmpty);
    final stopped = await fixture.api.cancelChatTurn(
      turnId: 'turn-3',
      generation: 3,
      attemptId: 'attempt-3',
      acknowledgeUnknown: false,
    );
    expect(stopped.outcomeUnknownAcknowledged, isFalse);
    expect(stopped.status, 'outcome_unknown');
    expect(stopped.recoverable, isFalse);
    expect(fixture.requests.single['operation'], 'cancel');
    expect(fixture.requests.single.containsKey('acknowledgeUnknown'), isFalse);
  });

  test('acknowledgement honors terminal races and rejects mismatched receipts',
      () async {
    var mismatch = <String, dynamic>{};
    final fixture = _ChatTransport((_, body) => _json({
          ..._receipt(body, status: 'completed', sequence: 9),
          'outcomeUnknownAcknowledged': false,
          'retryable': false,
          ...mismatch,
        }));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    Future<PandoraChatWireEvent> acknowledge() => fixture.api.cancelChatTurn(
          turnId: 'turn-3',
          generation: 3,
          attemptId: 'attempt-3',
          acknowledgeUnknown: true,
        );
    final completed = await acknowledge();
    expect(completed.status, 'completed');
    expect(completed.isTerminal, isTrue);
    expect(completed.outcomeUnknownAcknowledged, isFalse);
    expect(completed.outcomeUnknown, isFalse);
    for (final otherIdentity in <Map<String, dynamic>>[
      {'organizationId': 'another-scope'},
      {'turnId': 'another-turn'},
      {'attemptId': 'another-attempt'},
      {'generation': 4},
    ]) {
      mismatch = otherIdentity;
      await expectLater(acknowledge(), throwsFormatException);
    }
    expect(fixture.requests.length, 5);
    expect(
        fixture.requests.every((body) =>
            body['operation'] == 'cancel' &&
            body['clientAttemptId'] == 'attempt-3' &&
            body['expectedGeneration'] == 3),
        isTrue);
  });

  test('an unconfirmed acknowledgement never becomes a send or retry',
      () async {
    final fixture = _ChatTransport((_, body) => _json({
          'ok': false,
          'code': 'CHAT_OUTCOME_NOT_UNKNOWN',
          'accepted': true,
        }, status: 409));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    await expectLater(
        fixture.api.cancelChatTurn(
          turnId: 'turn-3',
          generation: 3,
          attemptId: 'attempt-3',
          acknowledgeUnknown: true,
        ),
        throwsA(isA<PandoraIntelligenceException>()
            .having((error) => error.code, 'code', 'CHAT_OUTCOME_NOT_UNKNOWN')
            .having(
                (error) => error.outcomeUnknown, 'outcomeUnknown', isTrue)));
    expect(fixture.requests.length, 1);
    expect(fixture.requests.single['operation'], 'cancel');
    expect(fixture.requests.single['acknowledgeUnknown'], isTrue);
  });

  test('cancelling unadmitted work retains its exact attempt without a thread',
      () async {
    var wrongAttempt = false;
    final fixture = _ChatTransport((_, request) => _json({
          ..._receipt(request, status: 'cancelled', sequence: 1),
          'found': true,
          'admitted': false,
          'admissionCancelled': true,
          'threadId': null,
          'activityJobId': null,
          'userMessageId': null,
          'assistantMessageId': null,
          'attemptId':
              wrongAttempt ? 'another-attempt' : request['clientAttemptId'],
          'retryable': false,
          'cancellationRequested': true,
        }));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    final cancelled = await fixture.api.cancelChatTurn(
        turnId: 'turn-not-admitted',
        generation: 1,
        attemptId: 'original-attempt');
    expect(cancelled.admissionCancelled, isTrue);
    expect(cancelled.threadId, isNull);
    expect(cancelled.attemptId, 'original-attempt');
    expect(fixture.requests.single['operation'], 'cancel');
    wrongAttempt = true;
    await expectLater(
        fixture.api.cancelChatTurn(
            turnId: 'turn-not-admitted',
            generation: 1,
            attemptId: 'original-attempt'),
        throwsFormatException);
    expect(fixture.requests.length, 2);
    expect(
        fixture.requests.every((request) => request['operation'] == 'cancel'),
        isTrue);
  });

  test(
      'history loads ordered messages and their failure receipt in one scoped RPC',
      () async {
    final failed = _receipt({
      'clientTurnId': 'turn-1',
      'clientAttemptId': 'attempt-1',
      'generation': 1
    }, status: 'failed_recoverably', sequence: 4);
    final fixture = _ChatTransport((_, request) => _json({
          'protocolVersion': 2,
          'threadId': _thread,
          'messages': [
            {
              'id': 'message-1',
              'thread_id': _thread,
              'author_role': 'user',
              'content': 'Please continue',
              'created_at': '2026-10-03T10:00:00Z',
              'chat_turn_id': 'turn-1',
              'chat_attempt_id': 'attempt-1',
              'chat_generation': 1,
              'turn_sequence': 1
            },
          ],
          'turns': [failed],
        }));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    final messages = await fixture.api.messages(_thread);
    expect(messages.single.turnReceipt!.status, 'failed_recoverably');
    expect(messages.single.turnId, 'turn-1');
    expect(messages.single.sequence, 1);
    expect(fixture.paths, ['/rest/v1/rpc/pandora_chat_thread_view_v2']);
    expect(fixture.requests.single, {'p_thread_id': _thread, 'p_limit': 200});
    expect(() => messages.clear(), throwsUnsupportedError);
  });

  test('history permission failures never fall back to a different read path',
      () async {
    final fixture = _ChatTransport((_, request) =>
        _json({'code': '42501', 'message': 'DENIED'}, status: 403));
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    await expectLater(fixture.api.messages(_thread),
        throwsA(isA<PandoraIntelligenceException>()));
    expect(fixture.paths, ['/rest/v1/rpc/pandora_chat_thread_view_v2']);
  });

  test(
      'older backend missing only the v2 history RPC uses scoped ordered v1 history',
      () async {
    final fixture = _ChatTransport((request, _) {
      if (request.url.path.contains('/rpc/')) {
        return _json({'code': 'PGRST202', 'message': 'RPC not present'},
            status: 404);
      }
      expect(
          request.url.queryParameters['organization_id'], 'eq.$_organization');
      expect(request.url.queryParameters['thread_id'], 'eq.$_thread');
      expect(request.url.queryParameters['order'],
          'created_at.desc.nullslast,id.desc.nullslast');
      return _json([
        {
          'id': 'b',
          'thread_id': _thread,
          'author_role': 'assistant',
          'content': 'Second',
          'created_at': '2026-10-03T10:00:01Z'
        },
        {
          'id': 'a',
          'thread_id': _thread,
          'author_role': 'user',
          'content': 'First',
          'created_at': '2026-10-03T10:00:00Z'
        },
      ]);
    });
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    expect(
        (await fixture.api.messages(_thread)).map((row) => row.id), ['a', 'b']);
    expect(fixture.paths.length, 2);
  });

  test('history rejects receipts or rows from another thread', () async {
    for (final incorrectReceipt in [true, false]) {
      final fixture = _ChatTransport((_, request) => _json({
            'protocolVersion': 2,
            'threadId': _thread,
            'messages': incorrectReceipt
                ? <Object>[]
                : [
                    {
                      'id': 'wrong',
                      'thread_id': 'another-thread',
                      'author_role': 'user',
                      'content': 'Hidden',
                      'created_at': '2026-10-03T10:00:00Z'
                    },
                  ],
            'turns': incorrectReceipt
                ? [
                    _receipt({
                      'clientTurnId': 'turn-1',
                      'clientAttemptId': 'attempt-1',
                      'generation': 1,
                      'threadId': 'another-thread'
                    }),
                  ]
                : <Object>[],
          }));
      await fixture.initialize();
      addTearDown(fixture.client.dispose);
      await expectLater(
          fixture.api.messages(_thread),
          throwsA(anyOf(
              isA<PandoraIntelligenceException>(), isA<FormatException>())));
      expect(fixture.paths.length, 1);
    }
  });
}
