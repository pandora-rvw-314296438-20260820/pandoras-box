import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';
import 'package:pandora_mobile/core/data/pandora_activity_history_api.dart';
import 'package:pandora_mobile/core/data/pandora_activity_stream_api.dart';

void main() {
  Map<String, dynamic> canonicalResult({
    required String eventId,
    required int sequence,
    required String admittedAt,
  }) =>
      <String, dynamic>{
        'schemaVersion': 1,
        'eventId': eventId,
        'jobId': 'job-1',
        'sequence': sequence,
        'writerEpoch': 2,
        'admittedBy': 'pandora-runtime',
        'admissionMode': 'online',
        'state': 'result',
        'message': 'Verified result.',
        'occurredAt': '2026-09-15T10:00:00.000Z',
        'admittedAt': admittedAt,
        'domain': 'chat',
        'capability': 'intelligence.chat',
        'executionId': 'exec-1',
        'provenance': <String, dynamic>{
          'sourceType': 'runtime',
          'sourceId': 'pandora-runtime',
          'sourceEventId': 'source-$eventId',
          'observedAt': '2026-09-15T10:00:00.000Z',
        },
        'evidence': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'verification_receipt',
            'relation': 'verification',
            'ref': 'verification:$eventId',
          },
        ],
        'blocker': null,
        'outcome': <String, dynamic>{
          'summary': 'Verified result.',
          'physicalDevice': false,
        },
      };

  Map<String, dynamic> historyItem(Map<String, dynamic> event) =>
      <String, dynamic>{
        'organizationId': 'org-1',
        'organizationName': 'Pandora',
        'requestedBy': 'user-1',
        'requestedByName': 'Owner',
        'threadId': 'thread-1',
        'projectId': 'project-1',
        'event': event,
      };

  test('History final activity is equivalent to the live canonical projection',
      () {
    final canonical = canonicalResult(
      eventId: 'event-3',
      sequence: 3,
      admittedAt: '2026-09-15T10:00:00.003Z',
    );
    final live = PandoraActivityProjection.fromJson(
      pandoraActivityPublicProjection(canonical),
    );
    final history = parsePandoraActivityHistoryPage(<String, dynamic>{
      'projectionVersion': 1,
      'items': <Map<String, dynamic>>[historyItem(canonical)],
      'hasMore': false,
      'nextCursor': null,
      'retentionBoundary': 'canonical_event_retention',
    }).items.single.activity;

    expect(history.eventId, live.eventId);
    expect(history.jobId, live.jobId);
    expect(history.sequence, live.sequence);
    expect(history.state, live.state);
    expect(history.message, live.message);
    expect(history.occurredAt, live.occurredAt);
    expect(history.admittedAt, live.admittedAt);
    expect(history.executionId, live.executionId);
    expect(history.source.sourceType, live.source.sourceType);
    expect(history.source.sourceId, live.source.sourceId);
    expect(history.source.sourceEventId, live.source.sourceEventId);
    expect(history.evidenceRefs.single.type, live.evidenceRefs.single.type);
    expect(history.evidenceRefs.single.relation,
        live.evidenceRefs.single.relation);
    expect(history.evidenceRefs.single.ref, live.evidenceRefs.single.ref);
    expect(history.outcome?.summary, live.outcome?.summary);
    expect(history.outcome?.physicalDevice, live.outcome?.physicalDevice);
  });

  test('History parser preserves server replay order and cursor identity', () {
    final newer = canonicalResult(
      eventId: 'event-3',
      sequence: 3,
      admittedAt: '2026-09-15T10:00:00.003Z',
    );
    final older = canonicalResult(
      eventId: 'event-2',
      sequence: 2,
      admittedAt: '2026-09-15T10:00:00.002Z',
    );
    final page = parsePandoraActivityHistoryPage(<String, dynamic>{
      'projectionVersion': 1,
      'items': <Map<String, dynamic>>[
        historyItem(newer),
        historyItem(older),
      ],
      'hasMore': true,
      'nextCursor': <String, dynamic>{
        'admittedAt': older['admittedAt'],
        'jobId': older['jobId'],
        'sequence': older['sequence'],
      },
      'retentionBoundary': 'canonical_event_retention',
    });

    expect(page.items.map((item) => item.activity.sequence), <int>[3, 2]);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor?.jobId, 'job-1');
    expect(page.nextCursor?.sequence, 2);
    expect(page.retentionBoundary, 'canonical_event_retention');
  });

  test('History page rejects a hasMore response without a bounded cursor', () {
    final canonical = canonicalResult(
      eventId: 'event-1',
      sequence: 1,
      admittedAt: '2026-09-15T10:00:00.001Z',
    );
    expect(
      () => parsePandoraActivityHistoryPage(<String, dynamic>{
        'projectionVersion': 1,
        'items': <Map<String, dynamic>>[historyItem(canonical)],
        'hasMore': true,
        'nextCursor': null,
        'retentionBoundary': 'canonical_event_retention',
      }),
      throwsFormatException,
    );
  });
}
