import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/pandora_user_admin_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _organization = '11111111-1111-4111-8111-111111111111';
const _otherOrganization = '22222222-2222-4222-8222-222222222222';
const _user = '33333333-3333-4333-8333-333333333333';

PandoraJson _membership({
  String organization = _organization,
  String name = 'Client membership name',
  String role = 'owner',
}) =>
    <String, dynamic>{
      'organization_id': organization,
      'role': role,
      'status': 'active',
      'created_at': '2026-10-02T00:00:00Z',
      'organizations': <String, dynamic>{
        'name': name,
        'slug': 'client-membership',
      },
    };

class _UserAdminFixture {
  _UserAdminFixture({
    this.memberships = const <PandoraJson>[],
    this.authorizationStatus = 200,
    this.authorization = const <String, dynamic>{
      'organization_id': _organization,
      'role': 'admin',
      'authority': 'explicit_operator_grant',
    },
  });

  final List<PandoraJson> memberships;
  final int authorizationStatus;
  final PandoraJson authorization;
  final requests = <http.Request>[];
  late final SupabaseClient client;

  List<http.Request> get authorizationRequests => requests
      .where((request) =>
          request.url.path ==
          '/rest/v1/rpc/pandora_core_authorize_user_admin_v1')
      .toList(growable: false);

  Future<void> initialize() async {
    final claims = base64Url
        .encode(utf8.encode(jsonEncode(<String, Object>{
          'sub': _user,
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        })))
        .replaceAll('=', '');

    // Every request terminates in this local fake. The token is test input.
    client = SupabaseClient(
      'https://user-admin.invalid',
      'test-placeholder',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final Object body;
        switch (request.url.path) {
          case '/auth/v1/token':
            body = <String, dynamic>{
              'access_token': 'eyJhbGciOiJub25lIn0.$claims.fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'test-placeholder',
              'user': <String, dynamic>{
                'id': _user,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.invalid',
                'created_at': '2026-10-03T00:00:00Z',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            };
          case '/rest/v1/memberships':
            body = memberships;
          case '/rest/v1/rpc/pandora_core_authorize_user_admin_v1':
            body = authorization;
          default:
            throw StateError('Unexpected test request: ${request.url}');
        }
        return http.Response(
          jsonEncode(body),
          request.url.path ==
                  '/rest/v1/rpc/pandora_core_authorize_user_admin_v1'
              ? authorizationStatus
              : 200,
          request: request,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'test-placeholder',
    );
  }
}

void main() {
  group('Scoped team organization access', () {
    test('retains the supplied client name and explicit operator authority',
        () async {
      final fixture = _UserAdminFixture(
        memberships: <PandoraJson>[
          _membership(
            organization: _otherOrganization,
            name: 'Unrelated organization name',
          ),
        ],
      );
      await fixture.initialize();
      final gateway = SupabasePandoraUserAdminGateway(
        client: fixture.client,
        organizationId: _organization,
        organizationName: 'Seabrook Operations',
      );

      final access = (await gateway.loadOrganizations()).single;

      expect(access.id, _organization);
      expect(access.name, 'Seabrook Operations');
      expect(access.role, 'admin');
      expect(access.authority, 'explicit_operator_grant');
      expect(access.isOperator, isTrue);
      expect(access.isOwner, isFalse);
      expect(fixture.authorizationRequests, hasLength(1));
      expect(
        jsonDecode(fixture.authorizationRequests.single.body),
        <String, dynamic>{
          'p_organization_id': _organization,
          'p_write': false,
        },
      );
    });

    for (final role in <String>['owner', 'admin']) {
      test('retains the target organization $role membership', () async {
        final fixture = _UserAdminFixture(
          memberships: <PandoraJson>[
            _membership(
              organization: _otherOrganization,
              name: 'Other organization',
            ),
            _membership(role: role),
          ],
          authorization: <String, dynamic>{
            'organization_id': _organization,
            'role': role,
            'authority': 'tenant_membership',
          },
        );
        await fixture.initialize();
        final gateway = SupabasePandoraUserAdminGateway(
          client: fixture.client,
          organizationId: _organization,
        );

        final access = (await gateway.loadOrganizations()).single;

        expect(access.id, _organization);
        expect(access.name, 'Client membership name');
        expect(access.slug, 'client-membership');
        expect(access.role, role);
        expect(access.authority, 'tenant_membership');
        expect(access.isOperator, isFalse);
        expect(access.isOwner, role == 'owner');
        expect(fixture.authorizationRequests, hasLength(1));
        final membershipRequest = fixture.requests.singleWhere(
          (request) => request.url.path == '/rest/v1/memberships',
        );
        expect(membershipRequest.url.queryParameters['user_id'], 'eq.$_user');
        expect(membershipRequest.url.queryParameters['status'], 'eq.active');
      });
    }

    for (final deniedAuthorization in <String, PandoraJson>{
      'another organization': <String, dynamic>{
        'organization_id': _otherOrganization,
        'role': 'admin',
        'authority': 'explicit_operator_grant',
      },
      'an unrecognized authority': <String, dynamic>{
        'organization_id': _organization,
        'role': 'owner',
        'authority': 'membership',
      },
      'a role without team administration access': <String, dynamic>{
        'organization_id': _organization,
        'role': 'member',
        'authority': 'explicit_operator_grant',
      },
    }.entries) {
      test('denies an operator grant for ${deniedAuthorization.key}', () async {
        final fixture = _UserAdminFixture(
          memberships: <PandoraJson>[_membership()],
          authorization: deniedAuthorization.value,
        );
        await fixture.initialize();
        final gateway = SupabasePandoraUserAdminGateway(
          client: fixture.client,
          organizationId: _organization,
        );

        await expectLater(
          gateway.loadOrganizations(),
          throwsA(
            isA<PandoraUserAdminFailure>().having(
              (failure) => failure.code,
              'code',
              'ORGANIZATION_ACCESS_REQUIRED',
            ),
          ),
        );
        final authorizationRequest = fixture.authorizationRequests.single;
        expect(authorizationRequest.method, 'POST');
        expect(jsonDecode(authorizationRequest.body), <String, dynamic>{
          'p_organization_id': _organization,
          'p_write': false,
        });
      });
    }

    test('HTTP 403 with Postgrest 42501 becomes a safe access denial',
        () async {
      final fixture = _UserAdminFixture(
        memberships: <PandoraJson>[_membership()],
        authorizationStatus: 403,
        authorization: <String, dynamic>{
          'code': '42501',
          'message': 'private_authorization_policy_details',
          'details': 'private_operator_grant_state',
          'hint': null,
        },
      );
      await fixture.initialize();
      final gateway = SupabasePandoraUserAdminGateway(
        client: fixture.client,
        organizationId: _organization,
        organizationName: 'Seabrook Operations',
      );

      await expectLater(
        gateway.loadOrganizations(),
        throwsA(
          isA<PandoraUserAdminFailure>()
              .having(
                (failure) => failure.code,
                'code',
                'ORGANIZATION_ACCESS_REQUIRED',
              )
              .having(
                (failure) => failure.message,
                'message',
                'Team administration is not authorized for this client.',
              ),
        ),
      );
      expect(fixture.authorizationRequests, hasLength(1));
      expect(
        jsonDecode(fixture.authorizationRequests.single.body),
        <String, dynamic>{
          'p_organization_id': _organization,
          'p_write': false,
        },
      );
    });

    test('unscoped organization loading does not request an operator grant',
        () async {
      final fixture = _UserAdminFixture();
      await fixture.initialize();
      final gateway = SupabasePandoraUserAdminGateway(client: fixture.client);

      expect(await gateway.loadOrganizations(), isEmpty);
      expect(fixture.authorizationRequests, isEmpty);
    });
  });

  group('Pandora team models', () {
    test('organization access defaults to ordinary tenant membership', () {
      const access = PandoraOrganizationAccess(
        id: _organization,
        name: 'Ordinary organization',
        role: 'owner',
      );

      expect(access.authority, 'tenant_membership');
      expect(access.isOperator, isFalse);
      expect(access.isOwner, isTrue);
    });

    test('normalizes member payloads and presentation labels', () {
      final member = PandoraTeamMember.fromJson(<String, dynamic>{
        'id': '11111111-1111-4111-8111-111111111111',
        'email': 'person@example.com',
        'displayName': 'Ada Lovelace',
        'role': 'operator',
        'status': 'active',
        'joinedAt': '2026-08-26T00:00:00Z',
      });

      expect(member.primaryLabel, 'Ada Lovelace');
      expect(member.initials, 'AL');
      expect(member.isActive, isTrue);
      expect(member.isInvited, isFalse);
      expect(member.joinedAt, isNotNull);
    });

    test('invite payload trims values without adding authority', () {
      const request = PandoraInviteRequest(
        email: ' PERSON@EXAMPLE.COM ',
        displayName: ' Person Name ',
        timezone: ' Asia/Manila ',
        role: 'member',
      );

      expect(request.toJson(), <String, dynamic>{
        'email': 'person@example.com',
        'displayName': 'Person Name',
        'timezone': 'Asia/Manila',
        'role': 'member',
      });
    });

    test('maps safe backend failure fields', () {
      final failure = PandoraUserAdminFailure.fromPayload(
        <String, dynamic>{
          'code': 'ROLE_GRANT_NOT_ALLOWED',
          'plainMessage': 'Only an owner can grant this role.',
          'requestId': 'request-123',
        },
        fallbackCode: 'FAILED',
        fallbackMessage: 'Failed.',
      );

      expect(failure.code, 'ROLE_GRANT_NOT_ALLOWED');
      expect(failure.message, 'Only an owner can grant this role.');
      expect(failure.requestId, 'request-123');
    });
  });
}
