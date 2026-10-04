import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pandora_mobile/core/data/pandora_activity_stream_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'device cancellation uses bounded RPC identity while unknown stages stay local',
      () async {
    const organization = '11111111-1111-4111-8111-111111111111';
    const job = '22222222-2222-4222-8222-222222222222';
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://activity-fixture.invalid',
      'test-placeholder',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200,
            request: request, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.dispose);
    // Simulated local session only; every HTTP request is intercepted above.
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'not-a-real-access-token',
      'token_type': 'bearer',
      'user': {
        'id': '33333333-3333-4333-8333-333333333333',
        'aud': 'authenticated',
        'role': 'authenticated',
        'created_at': '2026-10-03T00:00:00Z',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
      },
    }));
    final api =
        PandoraActivityStreamApi(client: client, organizationId: organization);
    final observedAt = DateTime.utc(2026, 10, 3, 18);
    await api.recordDeviceFact(
      jobId: job,
      operationId: 'device.cancel.fixture',
      capability: 'communication.sms',
      stage: 'cancelled',
      observedAt: observedAt,
    );
    expect(requests, hasLength(1));
    expect(requests.single.url.path,
        '/rest/v1/rpc/pandora_activity_device_fact_v1');
    expect(jsonDecode(requests.single.body), {
      'p_organization_id': organization,
      'p_job_id': job,
      'p_operation_id': 'device.cancel.fixture',
      'p_capability': 'communication.sms',
      'p_stage': 'cancelled',
      'p_observed_at': observedAt.toIso8601String(),
    });
    await expectLater(
      api.recordDeviceFact(
        jobId: job,
        operationId: 'device.cancel.fixture',
        capability: 'communication.sms',
        stage: 'invented',
        observedAt: observedAt,
      ),
      throwsA(isA<PandoraActivityStreamException>()),
    );
    expect(requests, hasLength(1));
  });

  test('canonical activity event becomes strict public projection', () {
    final event = <String, dynamic>{
      'schemaVersion': 1,
      'eventId': 'event-1',
      'jobId': 'job-1',
      'sequence': 1,
      'writerEpoch': 2,
      'admittedBy': 'pandora-runtime',
      'admissionMode': 'online',
      'state': 'acting',
      'message': 'Working on the request.',
      'occurredAt': '2026-09-14T12:00:00.000Z',
      'admittedAt': '2026-09-14T12:00:00.001Z',
      'domain': 'chat',
      'capability': 'intelligence.chat',
      'executionId': 'exec-1',
      'provenance': <String, dynamic>{
        'sourceType': 'runtime',
        'sourceId': 'pandora-runtime',
        'sourceEventId': 'source-1',
        'observedAt': '2026-09-14T12:00:00.000Z',
      },
      'evidence': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'runtime_event',
          'relation': 'source',
          'ref': 'runtime:event-1',
        },
      ],
      'blocker': null,
      'outcome': null,
    };

    final projection = pandoraActivityPublicProjection(event);

    expect(projection['projectionVersion'], 1);
    expect(projection['source'], event['provenance']);
    expect(projection['evidenceRefs'], event['evidence']);
    expect(projection.keys, <String>{
      'projectionVersion',
      'eventId',
      'jobId',
      'sequence',
      'state',
      'message',
      'occurredAt',
      'admittedAt',
      'domain',
      'capability',
      'executionId',
      'source',
      'evidenceRefs',
      'blocker',
      'outcome',
    });
    expect(projection.containsKey('writerEpoch'), isFalse);
    expect(projection.containsKey('admittedBy'), isFalse);
    expect(projection.containsKey('admissionMode'), isFalse);
    expect(projection.containsKey('provenance'), isFalse);
    expect(projection.containsKey('evidence'), isFalse);
  });
}
