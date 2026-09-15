import 'package:flutter_test/flutter_test.dart';
import 'package:pandora_mobile/core/activity/pandora_activity_projection.dart';

Map<String, dynamic> projection({
  int sequence = 1,
  String eventId = 'event-1',
  String jobId = 'job-1',
  String state = 'understanding',
  String message = 'Understanding the request.',
  List<Map<String, dynamic>> evidence = const [],
  Map<String, dynamic>? blocker,
  Map<String, dynamic>? outcome,
}) {
  final second = sequence.toString().padLeft(2, '0');
  return <String, dynamic>{
    'projectionVersion': 1,
    'eventId': eventId,
    'jobId': jobId,
    'sequence': sequence,
    'state': state,
    'message': message,
    'occurredAt': '2026-09-14T09:00:$second+00:00',
    'admittedAt': '2026-09-14T09:00:$second+00:00',
    'domain': 'chat',
    'capability': 'universal_chat',
    'executionId': 'exec-1',
    'source': <String, dynamic>{
      'sourceType': 'runtime',
      'sourceId': 'runtime-1',
      'sourceEventId': 'source-$sequence',
      'observedAt': '2026-09-14T09:00:$second+00:00',
    },
    'evidenceRefs': evidence,
    'blocker': blocker,
    'outcome': outcome,
  };
}

Map<String, dynamic> evidence(
  String type,
  String relation,
  String ref,
) =>
    <String, dynamic>{'type': type, 'relation': relation, 'ref': ref};

void main() {
  group('PandoraActivityProjection', () {
    test('parses the frozen public projection v1', () {
      final event = PandoraActivityProjection.fromJson(projection());

      expect(event.eventId, 'event-1');
      expect(event.jobId, 'job-1');
      expect(event.sequence, 1);
      expect(event.state, PandoraActivityState.understanding);
      expect(event.source.sourceEventId, 'source-1');
    });

    test('rejects unknown public fields instead of rendering them', () {
      final json = projection()..['rawToolArgs'] = '--secret';

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects non-opaque event identity', () {
      final json = projection(eventId: 'event with spaces');

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects duplicate evidence references', () {
      final duplicate = evidence('runtime_event', 'source', 'runtime:1');
      final json = projection(evidence: [duplicate, Map.of(duplicate)]);

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects unsupported Needs You reason codes', () {
      final json = projection(
        state: 'needs_you',
        blocker: <String, dynamic>{
          'reasonCode': 'because_i_said_so',
          'reason': 'A real boundary exists.',
          'requiredAction': 'Complete the required action.',
          'approvalRequired': false,
          'policyRef': null,
        },
      );

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('requires verification evidence for Result', () {
      final json = projection(
        state: 'result',
        message: 'Done.',
        outcome: <String, dynamic>{
          'summary': 'Request completed.',
          'physicalDevice': false,
        },
      );

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('requires device evidence for physical-device Result', () {
      final json = projection(
        state: 'result',
        message: 'Done.',
        evidence: [
          evidence(
            'verification_receipt',
            'verification',
            'verify:job-1',
          ),
        ],
        outcome: <String, dynamic>{
          'summary': 'Physical verification completed.',
          'physicalDevice': true,
        },
      );

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('accepts verified non-physical Result', () {
      final event = PandoraActivityProjection.fromJson(
        projection(
          state: 'result',
          message: 'Done.',
          evidence: [
            evidence(
              'verification_receipt',
              'verification',
              'verify:job-1',
            ),
          ],
          outcome: <String, dynamic>{
            'summary': 'Request completed.',
            'physicalDevice': false,
          },
        ),
      );

      expect(event.state, PandoraActivityState.result);
      expect(event.outcome?.physicalDevice, isFalse);
    });

    test('requires accepted control evidence for Resuming', () {
      final json = projection(state: 'resuming');

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('requires offset-aware timestamps', () {
      final json = projection()
        ..['occurredAt'] = '2026-09-14T09:00:01'
        ..['admittedAt'] = '2026-09-14T09:00:01';

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });
    test('rejects credential-like public text', () {
      final json = projection(
        message: 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456',
      );

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects impossible calendar timestamps', () {
      final json = projection()
        ..['occurredAt'] = '2026-02-31T09:00:01+00:00'
        ..['admittedAt'] = '2026-02-31T09:00:01+00:00';

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });

    test('rejects sequences above JavaScript safe integer range', () {
      final json = projection()..['sequence'] = 9007199254740992;

      expect(
        () => PandoraActivityProjection.fromJson(json),
        throwsFormatException,
      );
    });
  });
}
