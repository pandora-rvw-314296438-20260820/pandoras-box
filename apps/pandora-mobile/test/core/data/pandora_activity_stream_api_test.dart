import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/data/pandora_activity_stream_api.dart';

void main() {
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
