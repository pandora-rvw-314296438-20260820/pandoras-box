import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/chat/pandora_chat_controller.dart';
import 'package:pandora_mobile/core/config/pandora_acceptance_client.dart';
import 'package:pandora_mobile/core/config/pandora_runtime_binding.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/acceptance_profile_fixture.dart';

const _user = '33333333-3333-4333-8333-333333333333';
const _thread = '22222222-2222-4222-8222-222222222222';

http.StreamedResponse _json(Object body,
        {Map<String, String> headers = const {}}) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200,
        headers: {'content-type': 'application/json', ...headers});

Future<void> _signIn(SupabaseClient client) => client.auth
    .signInWithPassword(email: 'fixture@example.invalid', password: 'fixture')
    .then((_) {});

http.StreamedResponse _auth() {
  final claims = base64Url
      .encode(utf8.encode(jsonEncode({
        'sub': _user,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      })))
      .replaceAll('=', '');
  return _json({
    'access_token': 'eyJhbGciOiJub25lIn0.$claims.fixture',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'fixture',
    'user': {
      'id': _user,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'fixture@example.invalid',
      'created_at': '2026-10-03T00:00:00Z',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{}
    },
  });
}

void main() {
  final binding = acceptanceProfileBinding();
  final args = acceptanceProfileArguments();
  final organization = args['organizationId']!;
  SupabaseClient clientWith(
      FutureOr<http.StreamedResponse> Function(
              http.BaseRequest, Map<String, dynamic>)
          handler) {
    final client = PandoraAcceptanceClient.create(
        binding: binding,
        publishableKey: args['publishableKey']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient.streaming((request, bytes) async {
          final text = await bytes.bytesToString();
          if (request.url.path == '/auth/v1/token') return _auth();
          return handler(request,
              text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>);
        }));
    addTearDown(() => PandoraAcceptanceClient.dispose(client));
    return client;
  }

  Map<String, dynamic> receipt(Map<String, dynamic> request,
          {String status = 'completed'}) =>
      {
        'protocolVersion': 2,
        'organizationId': organization,
        'threadId': _thread,
        'turnId': request['clientTurnId'],
        'attemptId': request['clientAttemptId'],
        'generation': request['generation'],
        'activityJobId': 'fixture-activity',
        'userMessageId': 'fixture-user',
        'type': status,
        'status': status,
        'sequence': 2,
        if (status == 'completed') 'reply': 'Verified fixture reply.',
      };
  test('all three SDK invoke paths bind requests and verify response metadata',
      () async {
    final chat = PandoraChatController(scopeId: organization);
    addTearDown(chat.dispose);
    final dispatch = chat.submit('Fixture message').dispatch!;
    final requests = <Map<String, dynamic>>[];
    final client = clientWith((request, body) {
      expect(request.url.toString(),
          '${args['supabaseUrl']}/functions/v1/pandora-intelligence-chat');
      expect(request.followRedirects, isFalse);
      for (final header in binding.headers.entries) {
        expect(request.headers[header.key], header.value);
      }
      requests.add(body);
      if (body['protocolVersion'] != 2) {
        return _json(
            {'ok': true, 'threadId': _thread, 'reply': 'Legacy fixture reply.'},
            headers: binding.headers);
      }
      final full = {
        ...body,
        'clientTurnId': dispatch.token.turnId,
        'clientAttemptId': dispatch.token.attemptId,
        'generation': dispatch.token.generation
      };
      return _json(
          receipt(full,
              status:
                  body['operation'] == 'cancel' ? 'cancelled' : 'completed'),
          headers: binding.headers);
    });
    await _signIn(client);
    final api = PandoraIntelligenceApi(
        client: client, organizationId: organization, runtimeBinding: binding);
    expect((await api.executeChatTurn(dispatch).toList()).single.status,
        'completed');
    expect((await api.readChatTurn(turnId: dispatch.token.turnId))!.status,
        'completed');
    expect(
        (await api.cancelChatTurn(
                turnId: dispatch.token.turnId,
                attemptId: dispatch.token.attemptId,
                generation: 1))
            .status,
        'cancelled');
    expect(
        (await api.chat(message: 'Legacy', enterpriseContext: const {
          'selectedObject': {'coreMode': 'owner'}
        }))
            .reply,
        'Legacy fixture reply.');
    expect(requests, hasLength(4));
  });

  for (final wrongHeader in [null, ...binding.headers.keys]) {
    test(
        '${wrongHeader ?? 'missing metadata'} response binding cancels stream before any event',
        () async {
      var cancelled = false;
      final bytes =
          StreamController<List<int>>(onCancel: () => cancelled = true);
      addTearDown(() {
        unawaited(bytes.close());
      });
      var requests = 0;
      final client = clientWith((request, body) {
        requests++;
        bytes.add(utf8.encode('data: ${jsonEncode(receipt(body))}\n\n'));
        return http.StreamedResponse(bytes.stream, 200, headers: {
          'content-type': 'text/event-stream',
          if (wrongHeader != null) ...binding.headers,
          if (wrongHeader != null) wrongHeader: 'incorrect-fixture-binding',
        });
      });
      await _signIn(client);
      final api = PandoraIntelligenceApi(
          client: client,
          organizationId: organization,
          runtimeBinding: binding);
      final chat = PandoraChatController(scopeId: organization);
      addTearDown(chat.dispose);
      final events = <PandoraChatWireEvent>[];
      await expectLater(
          api.executeChatTurn(chat.submit('Hi').dispatch!).forEach(events.add),
          throwsA(isA<PandoraRuntimeBindingException>()
              .having((e) => e.code, 'code', 'ACCEPTANCE_RESPONSE_MISMATCH')));
      expect(events, isEmpty);
      expect(cancelled, isTrue);
      expect(requests, 1);
    });
  }
  test('control and legacy replies also require exact response binding',
      () async {
    final client = clientWith((_, __) => _json({'ok': true, 'found': false}));
    await _signIn(client);
    final api = PandoraIntelligenceApi(
        client: client, organizationId: organization, runtimeBinding: binding);
    final failure = throwsA(isA<PandoraRuntimeBindingException>()
        .having((e) => e.code, 'code', 'ACCEPTANCE_RESPONSE_MISMATCH'));
    await expectLater(api.readChatTurn(turnId: 'fixture-turn'), failure);
    await expectLater(
        api.cancelChatTurn(turnId: 'fixture-turn', generation: 1), failure);
    await expectLater(
        api.chat(message: 'Hi', enterpriseContext: const {
          'selectedObject': {'coreMode': 'owner'}
        }),
        failure);
  });
  test(
      'unguarded SDK client cannot claim acceptance even with matching URL and key',
      () {
    var calls = 0;
    final client = SupabaseClient(args['supabaseUrl']!, args['publishableKey']!,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    }));
    addTearDown(client.dispose);
    expect(
        () => PandoraIntelligenceApi(
            client: client,
            organizationId: organization,
            runtimeBinding: binding),
        throwsA(isA<PandoraRuntimeBindingException>()
            .having((e) => e.code, 'code', 'ACCEPTANCE_CLIENT_UNGUARDED')));
    expect(calls, 0);
  });
  test('wrong organization and mutated SDK key fail before HTTP', () async {
    var calls = 0;
    final client = clientWith((_, __) {
      calls++;
      return _json({});
    });
    expect(
        () => PandoraIntelligenceApi(
            client: client,
            organizationId: 'wrong-organization',
            runtimeBinding: binding),
        throwsA(isA<PandoraRuntimeBindingException>()));
    final api = PandoraIntelligenceApi(
        client: client, organizationId: organization, runtimeBinding: binding);
    client.functions.headers['apikey'] = 'sb_publishable_wrong_test_value';
    await expectLater(
        api.readChatTurn(turnId: 'fixture-turn'),
        throwsA(isA<PandoraRuntimeBindingException>()
            .having((e) => e.code, 'code', 'ACCEPTANCE_KEY_MISMATCH')));
    expect(calls, 0);
  });
  test('guard rejects arbitrary function paths before inner transport',
      () async {
    var calls = 0;
    final client = clientWith((_, __) {
      calls++;
      return _json({});
    });
    await _signIn(client);
    await expectLater(
        client.functions.invoke('unexpected-function'),
        throwsA(isA<PandoraRuntimeBindingException>().having(
            (e) => e.code, 'code', 'ACCEPTANCE_REQUEST_TARGET_MISMATCH')));
    expect(calls, 0);
  });

  test('verified SSE stays streaming and SDK cancellation reaches the response',
      () async {
    var cancelled = false;
    final bytes = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(() {
      unawaited(bytes.close());
    });
    final client = clientWith((_, __) => http.StreamedResponse(
        bytes.stream, 200,
        headers: {'content-type': 'text/event-stream', ...binding.headers}));
    await _signIn(client);
    final response = await client.functions.invoke(
        PandoraIntelligenceApi.functionName,
        headers: {'x-organization-id': organization, ...binding.headers},
        body: {'fixture': true});
    expect(response.data, isA<Stream<List<int>>>());
    final received = <int>[];
    final subscription =
        (response.data as Stream<List<int>>).listen(received.addAll);
    bytes.add(utf8.encode(': keepalive\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(utf8.decode(received), ': keepalive\n\n');
    expect(cancelled, isFalse);
    await subscription.cancel();
    expect(cancelled, isTrue);
  });

  test(
      'disposing an accepted SDK client closes its owned transport and fences reuse',
      () async {
    final inner = _CloseTrackingClient();
    final client = PandoraAcceptanceClient.create(
      binding: binding,
      publishableKey: args['publishableKey']!,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: inner,
    );
    PandoraAcceptanceClient.requireGuarded(client, binding);
    await PandoraAcceptanceClient.dispose(client);
    expect(inner.closed, isTrue);
    expect(
      () => PandoraIntelligenceApi(
          client: client,
          organizationId: organization,
          runtimeBinding: binding),
      throwsA(isA<PandoraRuntimeBindingException>().having(
          (error) => error.code, 'code', 'ACCEPTANCE_CLIENT_UNGUARDED')),
    );
    expect(inner.calls, 0);
  });

  test('redirect response cannot forward authentication and is cancelled',
      () async {
    var cancelled = false;
    final bytes = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(() {
      unawaited(bytes.close());
    });
    var calls = 0;
    final client = clientWith((request, _) {
      calls++;
      expect(request.followRedirects, isFalse);
      return http.StreamedResponse(bytes.stream, 302,
          headers: {'location': 'https://different.invalid'});
    });
    await _signIn(client);
    await expectLater(
        client.functions.invoke(PandoraIntelligenceApi.functionName,
            headers: {'x-organization-id': organization, ...binding.headers}),
        throwsA(isA<PandoraRuntimeBindingException>()
            .having((e) => e.code, 'code', 'ACCEPTANCE_REDIRECT_REJECTED')));
    expect(cancelled, isTrue);
    expect(calls, 1);
  });
}

class _CloseTrackingClient extends http.BaseClient {
  bool closed = false;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    return _json({});
  }

  @override
  void close() => closed = true;
}
