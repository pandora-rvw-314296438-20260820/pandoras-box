import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/pandora_intelligence_api.dart';
import 'package:pandora_mobile/core/security/pandora_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _organization = '11111111-1111-4111-8111-111111111111';
const _otherOrganization = '22222222-2222-4222-8222-222222222222';
const _entry = '33333333-3333-4333-8333-333333333333';
const _user = '44444444-4444-4444-8444-444444444444';
const _job = '55555555-5555-4555-8555-555555555555';

class _TransportFixture {
  _TransportFixture({this.operatorMode = false, this.denyActivity = false});
  final bool operatorMode;
  final bool denyActivity;
  final paths = <String>[];
  final activityPayloads = <Map<String, dynamic>>[];
  late final SupabaseClient client;

  Future<void> initialize() async {
    // All traffic uses this in-memory transport. These values are fabricated
    // test protocol input and cannot authenticate to any provider.
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
      httpClient: MockClient((request) async {
        final path = request.url.path;
        paths.add(path);
        Object body;
        var status = 200;
        if (path == '/auth/v1/token') {
          body = {
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
              'user_metadata': {'role': 'owner', 'is_admin': true}
            },
          };
        } else if (path == '/rest/v1/rpc/pandora_enterprise_my_workspaces_v1') {
          body = {'operator_mode': operatorMode, 'workspaces': <Object>[]};
        } else if (path == '/rest/v1/rpc/pandora_core_activity_begin_v1') {
          activityPayloads
              .add(jsonDecode(request.body) as Map<String, dynamic>);
          status = denyActivity ? 403 : 200;
          body = denyActivity
              ? {'code': '42501', 'message': 'ENTRY_REQUIRED'}
              : {'jobId': _job};
        } else if (path == '/functions/v1/pandora-intelligence-chat') {
          body = {
            'ok': true,
            'threadId': _job,
            'reply': 'Scoped workspace reply.'
          };
        } else {
          throw StateError('Unexpected test transport path: $path');
        }
        return http.Response(jsonEncode(body), status,
            request: request,
            headers: {'content-type': 'application/json'});
      }),
    );
    await client.auth.signInWithPassword(
        email: 'fixture@example.invalid', password: 'test-placeholder');
  }

  Map<String, Object?> context(
          {String mode = 'member', String organization = _organization}) =>
      {
        'surface': 'enterprise_overview',
        'route': '/enterprise/workspace/$organization/overview',
        'identityScope': 'enterprise_workspace',
        'selectedObject': {
          'workspaceMode': mode,
          'adapterKey': 'enterprise_core_v1',
          'organizationId': organization,
          if (mode == 'administrator') 'entryId': _entry
        },
      };

  PandoraIntelligenceApi get intelligence =>
      PandoraIntelligenceApi(client: client, organizationId: _organization);
}

void main() {
  for (final operatorMode in [false, true]) {
    test(
        'owner gate uses server operator_mode=$operatorMode, never editable metadata',
        () async {
      final fixture = _TransportFixture(operatorMode: operatorMode);
      await fixture.initialize();
      addTearDown(fixture.client.dispose);
      final auth = SupabasePandoraAuth(fixture.client);
      expect(await auth.hasActiveOwnerAccess(), operatorMode);
      expect(fixture.paths,
          contains('/rest/v1/rpc/pandora_enterprise_my_workspaces_v1'));
      expect(
          fixture.paths.any((path) => path.contains('/memberships')), isFalse);
    });
  }

  for (final mode in ['member', 'administrator']) {
    test('$mode chat verifies scoped activity authority before Edge execution',
        () async {
      final fixture = _TransportFixture();
      await fixture.initialize();
      addTearDown(fixture.client.dispose);
      final execution = await fixture.intelligence.startChatExecution(
          message: 'Show my tasks',
          requestId: 'transport-request-001',
          enterpriseContext: fixture.context(mode: mode));
      expect((await execution.turn).reply, 'Scoped workspace reply.');
      expect(fixture.activityPayloads.single, {
        'p_organization_id': _organization,
        'p_request_id': 'transport-request-001',
        'p_thread_id': null,
        'p_project_id': null,
        'p_entry_id': mode == 'administrator' ? _entry : null,
      });
      expect(fixture.paths.where((path) => path.contains('activity')),
          ['/rest/v1/rpc/pandora_core_activity_begin_v1']);
      expect(fixture.paths.last, '/functions/v1/pandora-intelligence-chat');
    });
  }

  test('activity denial never reaches Edge or legacy begin', () async {
    final fixture = _TransportFixture(denyActivity: true);
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    await expectLater(
        fixture.intelligence.startChatExecution(
            message: 'Show tasks',
            requestId: 'transport-request-denied',
            enterpriseContext: fixture.context(mode: 'administrator')),
        throwsA(isA<PandoraIntelligenceException>()));
    expect(fixture.paths.any((path) => path.contains('/functions/')), isFalse);
    expect(fixture.activityPayloads.length, 1);
  });

  test('mismatched client context makes no activity or Edge request', () async {
    final fixture = _TransportFixture();
    await fixture.initialize();
    addTearDown(fixture.client.dispose);
    await expectLater(
        fixture.intelligence.startChatExecution(
            message: 'Show tasks',
            requestId: 'transport-request-mismatch',
            enterpriseContext:
                fixture.context(organization: _otherOrganization)),
        throwsA(isA<PandoraIntelligenceException>()));
    expect(fixture.paths, ['/auth/v1/token']);
  });
}
